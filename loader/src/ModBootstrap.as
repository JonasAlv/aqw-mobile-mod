package {

	import flash.display.MovieClip;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.system.ApplicationDomain;
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

			// Safety net: suppress unhandled SecurityError #2070 across AIR runtime
			try {
				if (pocket.loaderInfo != null && "uncaughtErrorEvents" in pocket.loaderInfo) {
					var uee:* = pocket.loaderInfo["uncaughtErrorEvents"];
					if (uee != null) {
						uee.addEventListener("uncaughtError", function(event:*):void {
							if (event != null && event.error != null) {
								var errStr:String = event.error.toString();
								if (errStr.indexOf("2070") >= 0 || errStr.indexOf("SecurityError") >= 0) {
									trace("[Mod] Suppressed uncaught SecurityError: " + errStr);
									if ("preventDefault" in event) {
										event.preventDefault();
									}
								}
							}
						});
					}
				}
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

				try {
					var g:* = _pocket.game;
					var gDom:* = (g != null && g.loaderInfo != null) ? g.loaderInfo.applicationDomain : null;
					var airLoader:* = null;
					if (gDom != null && gDom.hasDefinition("types.AirLoader")) {
						airLoader = gDom.getDefinition("types.AirLoader");
					} else if (ApplicationDomain.currentDomain.hasDefinition("types.AirLoader")) {
						airLoader = ApplicationDomain.currentDomain.getDefinition("types.AirLoader");
					}
					if (airLoader != null) {
						if ("trust" in airLoader) {
							if (gDom != null) airLoader.trust(gDom);
							airLoader.trust(ApplicationDomain.currentDomain);
						}
						if ("trusted" in airLoader && airLoader.trusted != null) {
							if (gDom != null) airLoader.trusted[gDom] = true;
							airLoader.trusted[ApplicationDomain.currentDomain] = true;
						}
					}
				} catch (e:Error) {}

				// Initialize Haxe Api with the live game object
				Api.init(_pocket.game);
				try {
					Api.patchAirSecurity();
				} catch (e:Error) {}
			}
		}

	}

}
