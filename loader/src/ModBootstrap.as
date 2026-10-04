package {

	import flash.display.MovieClip;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.system.Security;
	import flash.utils.getDefinitionByName;

	import com.aqwapi.Api;
	import ui.ApiMenus;

	public class ModBootstrap {

		private static var _pocket:Pocket;
		private static var _gameInitialized:Boolean = false;

		public static function init(pocket:Pocket):void {
			_pocket = pocket;

			// 1. Initialize Haxe SWC runtime (static initializers and runtime shims)
			try {
				var haxeBoot:* = getDefinitionByName("haxe");
				if (haxeBoot != null && haxeBoot.initSwc != null) {
					haxeBoot.initSwc(null);
				}
			} catch (e:Error) {}

			try {
				Api.ensureMathShims();
			} catch (e:Error) {}

			try {
				Api.preloadAssets();
			} catch (e:Error) {}

			try {
				Security.allowDomain("*");
				Security.allowInsecureDomain("*");
			} catch (e:Error) {}

			// 2. Inject Mod Menus & Notifications
			if (pocket.overlay != null) {
				ApiMenus.inject(pocket.overlay);
			}

			// 3. Watch for game loading to initialize Api
			if (pocket.overlay != null) {
				pocket.overlay.addEventListener(Event.ENTER_FRAME, onEnterFrameCheckGame);
			}
		}

		private static function onEnterFrameCheckGame(e:Event):void {
			if (_gameInitialized) return;

			if (_pocket != null && _pocket.game != null) {
				_gameInitialized = true;
				if (_pocket.overlay != null) {
					_pocket.overlay.removeEventListener(Event.ENTER_FRAME, onEnterFrameCheckGame);
				}

				// Initialize Haxe Api with the live game object
				Api.init(_pocket.game);
			}
		}

	}

}
