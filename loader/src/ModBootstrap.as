package {

	import flash.display.MovieClip;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.system.Security;

	import com.aqwapi.AqwApi;
	import ui.ApiMenus;
	import util.HelperSetting;
	import flash.utils.getDefinitionByName;

	POCKET::IS_DESKTOP {
		import controller.gamepad.DesktopInputManager;
	}

	public class ModBootstrap {

		private static var _pocket:Pocket;
		private static var _gameInitialized:Boolean = false;

		public static function init(pocket:Pocket):void {
			_pocket = pocket;

			// Initialize Haxe SWC runtime (static initializers and runtime shims)
			try {
				var haxeBoot:* = getDefinitionByName("haxe");
				if (haxeBoot != null && haxeBoot.initSwc != null) {
					haxeBoot.initSwc(null);
				}
			} catch (e:Error) {}

			try {
				AqwApi.ensureMathShims();
			} catch (e:Error) {}

			try {
				Security.allowDomain("*");
				Security.allowInsecureDomain("*");
			} catch (e:Error) {}

			// 1. Initialize SWF RAM cache setting
			if (pocket.config != null) {
				pocket.config.option_swf_cache = HelperSetting.getBool(HelperSetting.OPTION_SWF_CACHE);
			}

			// 2. Initialize Gamepad support on Desktop
			POCKET::IS_DESKTOP {
				new DesktopInputManager(pocket);
			}

			// 3. Inject Mod Menus & Notifications
			if (pocket.overlay != null) {
				ApiMenus.inject(pocket.overlay);
			}

			// 4. Watch for game loading to initialize AqwApi
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

				// Initialize Haxe AqwApi with the live game object
				AqwApi.init(_pocket.game);
			}
		}

	}

}

