package ui {
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.text.TextField;
	import flash.text.TextFormat;
	import flash.text.TextFormatAlign;
	import flash.utils.Timer;
	import flash.events.TimerEvent;

	public class ApiNotification extends Sprite {

		private static const DISMISS_DELAY:Number = 4000;
		private static const FADE_SPEED:Number = 0.06;
		private static const WIDTH:Number = 300;
		private static const HEIGHT:Number = 42;

		private var _messageTxt:TextField;
		private var _closeBtn:Sprite;
		private var _accentBar:Sprite;
		private var _timer:Timer;
		private var _onDismiss:Function;
		private var _isHovered:Boolean = false;
		private var _slideOffset:Number = WIDTH;
		public var id:String;
		public var sticky:Boolean;

		public function ApiNotification(id:String, message:String, sticky:Boolean = false) {
			this.id = id;
			this.sticky = sticky;
			this.graphics.beginFill(0x0d0d0d, 0.95);
			this.graphics.lineStyle(1, 0x1a1a1a);
			this.graphics.drawRoundRect(0, 0, WIDTH, HEIGHT, 6, 6);
			this.graphics.endFill();

			_accentBar = new Sprite();
			_accentBar.graphics.beginFill(0x4a9eff, 1);
			_accentBar.graphics.drawRoundRect(0, 0, 4, HEIGHT, 2, 2);
			_accentBar.graphics.endFill();
			this.addChild(_accentBar);

			_messageTxt = new TextField();
			_messageTxt.defaultTextFormat = new TextFormat("_sans", 13, 0xE8E8E8, true, null, null, null, null, TextFormatAlign.LEFT);
			_messageTxt.text = message;
			_messageTxt.width = WIDTH - 56;
			_messageTxt.height = 30;
			_messageTxt.x = 12;
			_messageTxt.y = 6;
			_messageTxt.selectable = false;
			_messageTxt.mouseEnabled = false;
			this.addChild(_messageTxt);

			_closeBtn = new Sprite();
			_closeBtn.graphics.beginFill(0x1a1a1a, 1);
			_closeBtn.graphics.drawRoundRect(WIDTH - 22, 6, 18, 18, 3, 3);
			_closeBtn.graphics.endFill();
			_closeBtn.buttonMode = true;
			_closeBtn.visible = !sticky;
			_closeBtn.mouseEnabled = !sticky;

			var closeTxt:TextField = new TextField();
			closeTxt.defaultTextFormat = new TextFormat("_sans", 12, 0x888888, false, null, null, null, null, TextFormatAlign.CENTER);
			closeTxt.text = "\u2715";
			closeTxt.width = 18;
			closeTxt.height = 18;
			closeTxt.y = 7;
			closeTxt.selectable = false;
			closeTxt.mouseEnabled = false;
			_closeBtn.addChild(closeTxt);
			this.addChild(_closeBtn);

			this.addEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
			this.addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
			this.addEventListener(MouseEvent.CLICK, onClick);
			_closeBtn.addEventListener(MouseEvent.CLICK, onCloseClick);

			if (!sticky) {
				_timer = new Timer(DISMISS_DELAY, 1);
				_timer.addEventListener(TimerEvent.TIMER, onDismissTimer);
				_timer.start();
			}

			this.addEventListener(Event.ENTER_FRAME, onEnterFrame);
		}

		public function setOnDismiss(fn:Function):void {
			_onDismiss = fn;
		}

		public function dismiss():void {
			if (_timer) { _timer.stop(); _timer = null; }
			this.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
			this.addEventListener(Event.ENTER_FRAME, onFadeOut);
		}

		private function onMouseOver(e:MouseEvent):void {
			_isHovered = true;
			if (_timer) { _timer.stop(); }
		}

		private function onMouseOut(e:MouseEvent):void {
			_isHovered = false;
			if (_timer) { _timer.start(); }
		}

		private function onClick(e:MouseEvent):void {
			dismiss();
		}

		private function onCloseClick(e:MouseEvent):void {
			dismiss();
		}

		private function onDismissTimer(e:TimerEvent):void {
			dismiss();
		}

		private function onEnterFrame(e:Event):void {
			if (_slideOffset > 0) {
				_slideOffset -= 8;
				if (_slideOffset < 0) { _slideOffset = 0; }
			}
			this.x = WIDTH + _slideOffset;
		}

		private function onFadeOut(e:Event):void {
			this.alpha -= FADE_SPEED;
			if (this.alpha <= 0) {
				if (_onDismiss != null) { _onDismiss(this); }
			}
		}

		public function destroy():void {
			if (_timer) { _timer.stop(); _timer = null; }
			this.removeEventListener(Event.ENTER_FRAME, onEnterFrame);
			this.removeEventListener(Event.ENTER_FRAME, onFadeOut);
			this.removeEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
			this.removeEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
			this.removeEventListener(MouseEvent.CLICK, onClick);
			if (_closeBtn != null) { _closeBtn.removeEventListener(MouseEvent.CLICK, onCloseClick); }
			if (this.parent != null) { this.parent.removeChild(this); }
		}
	}
}
