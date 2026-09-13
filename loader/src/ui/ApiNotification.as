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
		private static const FADE_SPEED:Number = 0.07;
		private static const WIDTH:Number = 280;
		private static const HEIGHT:Number = 38;

		private var _messageTxt:TextField;
		private var _closeBtn:Sprite;
		private var _timer:Timer;
		private var _onDismiss:Function;
		private var _fading:Boolean = false;
		public var id:String;
		public var sticky:Boolean;

		public function ApiNotification(id:String, message:String, sticky:Boolean = false) {
			this.id = id;
			this.sticky = sticky;

			// Background
			this.graphics.beginFill(0x111111, 0.92);
			this.graphics.drawRect(0, 0, WIDTH, HEIGHT);
			this.graphics.endFill();

			// Blue left accent bar
			this.graphics.beginFill(0x4a9eff, 1);
			this.graphics.drawRect(0, 0, 4, HEIGHT);
			this.graphics.endFill();

			// Message text
			_messageTxt = new TextField();
			var fmt:TextFormat = new TextFormat("_sans", 12, 0xEEEEEE, true);
			fmt.align = TextFormatAlign.LEFT;
			_messageTxt.defaultTextFormat = fmt;
			_messageTxt.text = message;
			_messageTxt.width = WIDTH - (sticky ? 16 : 36);
			_messageTxt.height = HEIGHT;
			_messageTxt.x = 10;
			_messageTxt.y = 0;
			_messageTxt.selectable = false;
			_messageTxt.mouseEnabled = false;
			this.addChild(_messageTxt);

			// Close button — drawn entirely with vectors (no text/icon dependency)
			if (!sticky) {
				_closeBtn = new Sprite();
				_closeBtn.buttonMode = true;
				_closeBtn.useHandCursor = true;

				// X shape drawn with lines
				var cx:Number = WIDTH - 16;
				var cy:Number = HEIGHT / 2;
				var r:Number = 5;
				_closeBtn.graphics.lineStyle(2, 0x888888, 1);
				_closeBtn.graphics.moveTo(cx - r, cy - r);
				_closeBtn.graphics.lineTo(cx + r, cy + r);
				_closeBtn.graphics.moveTo(cx + r, cy - r);
				_closeBtn.graphics.lineTo(cx - r, cy + r);

				// Invisible hit area
				_closeBtn.graphics.beginFill(0x000000, 0);
				_closeBtn.graphics.drawRect(cx - r - 4, cy - r - 4, (r + 4) * 2, (r + 4) * 2);
				_closeBtn.graphics.endFill();

				_closeBtn.addEventListener(MouseEvent.CLICK, onCloseClick);
				_closeBtn.addEventListener(MouseEvent.MOUSE_OVER, onCloseBtnOver);
				_closeBtn.addEventListener(MouseEvent.MOUSE_OUT, onCloseBtnOut);
				this.addChild(_closeBtn);
			}

			this.addEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
			this.addEventListener(MouseEvent.MOUSE_OUT, onMouseOut);

			if (!sticky) {
				_timer = new Timer(DISMISS_DELAY, 1);
				_timer.addEventListener(TimerEvent.TIMER, onDismissTimer);
				_timer.start();
			}

			this.alpha = 0;
			this.addEventListener(Event.ENTER_FRAME, onFadeIn);
		}

		public function setOnDismiss(fn:Function):void {
			_onDismiss = fn;
		}

		public function dismiss():void {
			if (_fading) return;
			_fading = true;
			if (_timer) { _timer.stop(); _timer = null; }
			this.removeEventListener(Event.ENTER_FRAME, onFadeIn);
			this.addEventListener(Event.ENTER_FRAME, onFadeOut);
		}

		private function onMouseOver(e:MouseEvent):void {
			if (_timer) _timer.stop();
		}

		private function onMouseOut(e:MouseEvent):void {
			if (_timer) _timer.start();
		}

		private function onCloseBtnOver(e:MouseEvent):void {
			if (_closeBtn == null) return;
			_closeBtn.graphics.clear();
			var cx:Number = WIDTH - 16;
			var cy:Number = HEIGHT / 2;
			var r:Number = 5;
			_closeBtn.graphics.lineStyle(2, 0xffffff, 1);
			_closeBtn.graphics.moveTo(cx - r, cy - r);
			_closeBtn.graphics.lineTo(cx + r, cy + r);
			_closeBtn.graphics.moveTo(cx + r, cy - r);
			_closeBtn.graphics.lineTo(cx - r, cy + r);
			_closeBtn.graphics.beginFill(0x000000, 0);
			_closeBtn.graphics.drawRect(cx - r - 4, cy - r - 4, (r + 4) * 2, (r + 4) * 2);
			_closeBtn.graphics.endFill();
		}

		private function onCloseBtnOut(e:MouseEvent):void {
			if (_closeBtn == null) return;
			_closeBtn.graphics.clear();
			var cx:Number = WIDTH - 16;
			var cy:Number = HEIGHT / 2;
			var r:Number = 5;
			_closeBtn.graphics.lineStyle(2, 0x888888, 1);
			_closeBtn.graphics.moveTo(cx - r, cy - r);
			_closeBtn.graphics.lineTo(cx + r, cy + r);
			_closeBtn.graphics.moveTo(cx + r, cy - r);
			_closeBtn.graphics.lineTo(cx - r, cy + r);
			_closeBtn.graphics.beginFill(0x000000, 0);
			_closeBtn.graphics.drawRect(cx - r - 4, cy - r - 4, (r + 4) * 2, (r + 4) * 2);
			_closeBtn.graphics.endFill();
		}

		private function onCloseClick(e:MouseEvent):void {
			e.stopPropagation();
			dismiss();
		}

		private function onDismissTimer(e:TimerEvent):void {
			dismiss();
		}

		private function onFadeIn(e:Event):void {
			this.alpha += FADE_SPEED * 2;
			if (this.alpha >= 1) {
				this.alpha = 1;
				this.removeEventListener(Event.ENTER_FRAME, onFadeIn);
			}
		}

		private function onFadeOut(e:Event):void {
			this.alpha -= FADE_SPEED;
			if (this.alpha <= 0) {
				this.alpha = 0;
				this.removeEventListener(Event.ENTER_FRAME, onFadeOut);
				if (this.parent != null) this.parent.removeChild(this);
				if (_onDismiss != null) _onDismiss(this);
			}
		}

		public function destroy():void {
			if (_timer) { _timer.stop(); _timer = null; }
			this.removeEventListener(Event.ENTER_FRAME, onFadeIn);
			this.removeEventListener(Event.ENTER_FRAME, onFadeOut);
			this.removeEventListener(MouseEvent.MOUSE_OVER, onMouseOver);
			this.removeEventListener(MouseEvent.MOUSE_OUT, onMouseOut);
			if (_closeBtn != null) {
				_closeBtn.removeEventListener(MouseEvent.CLICK, onCloseClick);
				_closeBtn.removeEventListener(MouseEvent.MOUSE_OVER, onCloseBtnOver);
				_closeBtn.removeEventListener(MouseEvent.MOUSE_OUT, onCloseBtnOut);
			}
			if (this.parent != null) this.parent.removeChild(this);
		}
	}
}
