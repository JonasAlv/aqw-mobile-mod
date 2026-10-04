package ui.util {

	import flash.display.MovieClip;
	import flash.display.SimpleButton;
	import flash.text.TextField;

	public class Pagination extends MovieClip {

		public var tPage:TextField;
		public var btnPrev:SimpleButton;
		public var btnNext:SimpleButton;

		public var fData:Object = {};
		public var sel:Object = {};

		private static const DISABLED_ALPHA:Number = 0.4;

		public function fOpen(fData:Object):void {
			this.fData = fData;
			refresh();
		}

		public function update(fData:Object):void {
			this.fData = fData;
			refresh();
		}

		private function refresh():void {
			if (fData == null) {
				return;
			}

			if (tPage) {
				tPage.text = "Page " + fData.page + " of " + fData.totalPages;
			}

			setButtonState(btnPrev, fData.canPrev);
			setButtonState(btnNext, fData.canNext);
		}

		private function setButtonState(btn:SimpleButton, enabled:Boolean):void {
			if (btn == null) {
				return;
			}

			btn.mouseEnabled = enabled;
			btn.alpha = enabled ? 1 : DISABLED_ALPHA;
		}

		public function fClose():void {
			fData = null;
			parent.removeChild(this);
		}

	}

}