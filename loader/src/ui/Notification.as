package ui {

	import flash.display.SimpleButton;
	import flash.display.Sprite;
	import flash.events.MouseEvent;
	import flash.text.TextField;

	public class Notification extends Sprite {

		public var id:String;
		private var _sticky:Boolean;

		public function Notification(message:String, sticky:Boolean = false) {
			this._sticky = sticky;
			this.messageTxt.htmlText = message;

			this.closeBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void { onClose(); }, false, 0, true);
		}

		public var messageTxt:TextField;
		public var closeBtn:SimpleButton;

		public function onClose():void {
			if (this.parent) {
				this.parent.removeChild(this);
			}
		}

		public function get sticky():Boolean {
			return _sticky;
		}

	}
}
