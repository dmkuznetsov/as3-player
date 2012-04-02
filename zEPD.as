/**
 * @author Dmitry Kuznetsov <dev.kuznetsov@gmail.com>
 */
package
{
    import flash.utils.ByteArray;
    import flash.media.ID3Info;
    import flash.display.Sprite;
    import flash.external.ExternalInterface;
    import flash.utils.Timer;
    import flash.media.Sound;
    import flash.media.SoundChannel;
    import flash.media.SoundTransform;
    import flash.media.SoundLoaderContext;
    import flash.events.Event;
    import flash.events.ProgressEvent;
    import flash.events.TimerEvent;
    import flash.events.IOErrorEvent;
    import flash.events.SecurityErrorEvent;
    import flash.net.URLRequest;

    public class Radio extends Sprite
    {
        private var _sound:Sound;
        private var _channel:SoundChannel;
        private var _url:String;
        private var _playTimer:Timer;
        
        private var _isPlaying:Boolean = false;
        private var _isStreaming:Boolean = true;
        private var _isBuffering:Boolean = false;
        private var _debug:Boolean = false;

        private var _volume:int = 100;
        private var _pausePosition:int = 0;
        private var _bufferTime:int = 10000;
        //private var _progressInterval:int = 1000;

        //private var _callback:Array;

        public function Radio():void
        {
            if ( ExternalInterface.available )
            {
                try
                {
                    //this._callback[ "debug" ] = "fromPlayer";
                    //this._callback[ "error" ] = "playerError";
                    //ExternalInterface.addCallback( "setCallback", setCallback );
                    //ExternalInterface.addCallback( "getCallback", getCallback );
                    ExternalInterface.addCallback( "debug", debug );
                    ExternalInterface.addCallback( "setUrl", setUrl );
                    ExternalInterface.addCallback( "getUrl", getUrl );
                    ExternalInterface.addCallback( "play", _load );
                    ExternalInterface.addCallback( "pause", pause );
                    ExternalInterface.addCallback( "stop", stop );
                    ExternalInterface.addCallback( "setVolume", setVolume );
                    ExternalInterface.addCallback( "getVolume", getVolume );
                    if ( !_checkExternalReady() )
                    {
                        trace( "External is not ready, creating timer.\n" );
                        var readyTimer:Timer = new Timer( 100, 0 );
                        readyTimer.addEventListener( TimerEvent.TIMER, _timerCheckExternalReady );
                        readyTimer.start();
                    }
                }
                catch ( error:SecurityError )
                {
                    trace( "A SecurityError occurred: " + error.message + "\n" );
                }
                catch ( error:Error )
                {
                    trace( "An Error occurred: " + error.message + "\n" );
                }
            }
            else
            {
                trace( "External interface is not available for this container." );
            }
        }

        /**
         * Set callback functioms
         *
        public function setCallback( event:String, method:String ):void
        {
            if ( this._callback[ event ] )
            {
                this._callback[ event ] = method;
            }
        }*/

        /**
         * Get callback function by event
         *
        public function getCallback( event:String ):String
        {
            var result:String = "";
            if ( this._callback[ event ] )
            {
                result = this._callback[ event ];
            }
            return result;
        }*/

        /**
         * Send message to external
         */
        public function externalDebug( value:String ):void
        {
            if( this._debug && ExternalInterface.available )
            {
                ExternalInterface.call( "playerDebug", value );
            }
        }

        /**
         * Send error message to external
         */
        public function externalError( value:String ):void
        {
            if ( ExternalInterface.available )
            {
                ExternalInterface.call( "playerError", value );
            }
        }
        
        /**
         * Send message of change status of buffering
         */
        public function externalBuffering( boof:Boolean ):void
        {
            if ( ExternalInterface.available )
            {
                ExternalInterface.call( "playerBuffering", boof );
            }
        }

        
        /**
         * Endble/disable debug mode
         */
        public function debug( enable:Boolean ):void
        {
            this._debug = enable;
        }

        
        /**
         * Set url of audio stream
         */
        public function setUrl( url:String, isStreaming:Boolean = true ):void
        {
            this._url = url;
            this._isStreaming = isStreaming;
            this.externalDebug( "Set url: " + url );
        }
        
        /**
         * Get url of current audio stream
         */
        public function getUrl():String
        {
            return this._url;
        }
        
        /**
         * Play sound begin from position
         */
        public function play( position:int = 0 ):void
        {
            if ( !this._isPlaying )
            {
                if ( this._pausePosition != 0 )
                {
                    position = this._pausePosition;
                    this._pausePosition = 0;
                }
                this._channel = this._sound.play( position, 0, null );
                this.setVolume( this._volume );
                this._isPlaying = true;
                this._channel.addEventListener( Event.SOUND_COMPLETE, _listenerOnPlayComplete );

                this.externalDebug( "Buffer time - " + this._bufferTime );
                this.externalDebug( "Start playing from - " + position );
                
                this._playTimer = new Timer( 50, 0 );
                this._playTimer.addEventListener( TimerEvent.TIMER, _listenerSetBuffering );
                this._playTimer.start();
            }
        }

        /**
         * Pause of listening
         */
        public function pause():void
        {
            this.stop( this._channel.position );
        }

        /**
         * Stop of playing sound
         */
        public function stop( position:int = 0 ):void
        {
            if ( this._isPlaying )
            {
                this._pausePosition = position;
                this._channel.stop();
                if ( position == 0 )
                {
                    this._sound.close();
                }
                this._isPlaying = false;
                this.externalDebug( "Stop playing" );
                this._playTimer.stop();
            }
        }
        
        /**
         * Set volume
         */
        public function setVolume( volume:int ):void
        {
            volume = volume > 100 ? 100 : volume;
            volume = volume < 0 ? 0 : volume;
            this._volume = volume;
            if( this._isPlaying )
            {
                var soundTransform:SoundTransform = this._channel.soundTransform;
                soundTransform.volume = volume / 100;
                this._channel.soundTransform = soundTransform;
            }
            this.externalDebug( "Set volume - " + volume );
        }
        
        /**
         * Get volume
         */
        public function getVolume():int
        {
            return this._volume;
        }


        /**
         * Load audio stream
         */
        protected function _load():void
        {
            if ( this._isPlaying )
            {
                this.stop();
            }
            //this._isLoaded = false;

            this._sound = new Sound();
            this._sound.addEventListener( ProgressEvent.PROGRESS, _listenerOnLoadProgress );
            this._sound.addEventListener( Event.OPEN, _listenerOnLoadOpen );
            this._sound.addEventListener( Event.COMPLETE, _listenerOnLoadComplete );
            this._sound.addEventListener( Event.ID3, _listenerOnID3 );
            this._sound.addEventListener( IOErrorEvent.IO_ERROR, _listenerOnError );
            this._sound.addEventListener( SecurityErrorEvent.SECURITY_ERROR, _listenerOnError );
            
            var loaderContext:SoundLoaderContext = new SoundLoaderContext( this._bufferTime, false );
            var urlRequest:URLRequest = new URLRequest( this._url );
            this._sound.load( urlRequest, loaderContext );
        }

        /**
         * Check play or buffering now
         */
        protected function _listenerSetBuffering( event:TimerEvent ):void
        {
            if ( this._isPlaying )
            {
                if ( this._isBuffering != this._sound.isBuffering )
                {
                    this._isBuffering = this._sound.isBuffering;
                    this.externalBuffering( this._isBuffering );
                }
            }
        }


        private function _listenerOnPlayComplete( event:ProgressEvent ):void
        {
            this.externalDebug( "Play complete" );
        }

        
        private function _listenerOnLoadProgress( event:ProgressEvent ):void
        {
            this.externalDebug( "Loaded - " + event.bytesLoaded );
        }

        private function _listenerOnLoadOpen( event:Event ):void
        {
            if ( this._isStreaming )
            {
                this.play();
            }
            this.externalDebug( "onLoadOpen" );
        }

        private function _listenerOnLoadComplete( event:Event ):void
        {
            //this._isLoaded = true;
            if ( !this._isPlaying )
            {
                this.play();
            }
            this.externalDebug( "onLoadComplete" );
        }

        private function _listenerOnID3( event:Event ):void
        {
            var id3:ID3Info = event.target.id3;
            var result:String = "ID3 tag \n";
            for ( var propName:String in id3 )
            {
                result += propName + " = " + id3[ propName ] + "\n";
            }
            this.externalDebug( result );
        }

        private function _listenerOnError( event:Event ):void
        {
            this.externalError( event.target.valueOf );
            //this.toExternal( "Listener: ERROR - " + event.formatToString );
        }
    
        
// **********

        private function _checkExternalReady():Boolean
        {
            var isReady:Boolean = ExternalInterface.call( "isReady" );
            return isReady;
        }
        
        private function _timerCheckExternalReady( event:TimerEvent ):void
        {
            var isReady:Boolean = _checkExternalReady();
            if ( isReady )
            {
                Timer( event.target ).stop();
            }
        }
    }
}