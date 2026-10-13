package {

	import flash.display.Loader;
	import flash.display.MovieClip;
	import flash.display.Sprite;
	import flash.events.Event;
	import flash.net.URLRequest;
	import flash.system.ApplicationDomain;
	import flash.system.LoaderContext;
	import flash.system.Security;
	import flash.utils.getDefinitionByName;

	import com.aqwapi.Api;
	import ui.ApiMenus;

	public class ModBootstrap {

		private static var _pocket:*;
		private static var _gameInitialized:Boolean = false;

		public static function init(pocket:*):void {
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
				if (pocket != null && pocket.loaderInfo != null && "uncaughtErrorEvents" in pocket.loaderInfo) {
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
			if (pocket != null && "overlay" in pocket && pocket.overlay != null) {
				ApiMenus.inject(pocket.overlay);
			}

			// 3. Watch for game loading to initialize Api
			if (pocket != null && "overlay" in pocket && pocket.overlay != null) {
				pocket.overlay.addEventListener(Event.ENTER_FRAME, onEnterFrameCheckGame);
			}
		}

		public static function initStandalone(game:*, stage:*):void {
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

			// 2. Initialize Haxe Api with the live game object
			try {
				Api.init(game);
			} catch (e:Error) {
				trace("[Mod] API init error: " + e);
			}

			// 3. Inject standalone UI
			try {
				ApiMenus.injectStandalone(stage);
			} catch (e:Error) {
				trace("[Mod] Menu inject error: " + e);
			}

			// 4. Setup Map override to load vendor world-map.swf
			setupMapOverride(game);
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

				// Setup vendor map override
				setupMapOverride(_pocket.game);
			}
		}

		public static function setupMapOverride(game:*):void {
			if (game == null) return;
			try {
				var loadVendorMap:Function = function():void {
					try {
						if (game.ui != null && game.ui.mcPopup != null && game.ui.mcPopup.mcMap != null) {
							var mcMap:* = game.ui.mcPopup.mcMap;
							while (mcMap.numChildren > 0) {
								mcMap.removeChildAt(0);
							}
							var ldr:Loader = new Loader();
							var ctx:LoaderContext = new LoaderContext(false, ApplicationDomain.currentDomain);
							ldr.load(new URLRequest("app:/gamefiles/world-map.swf"), ctx);
							mcMap.addChild(ldr);
						}
					} catch (e:Error) {
						trace("[Mod] Error loading vendor map: " + e);
					}
				};

				var hookPopup:Function = function():void {
					try {
						var appDom:ApplicationDomain = ApplicationDomain.currentDomain;
						if (appDom != null && appDom.hasDefinition("spider_fla.mcPopup_355")) {
							var popCls:Class = appDom.getDefinition("spider_fla.mcPopup_355") as Class;
							if (popCls != null && popCls.prototype != null) {
								popCls.prototype.loadMap = function(param1:* = null):* {
									loadVendorMap();
									return null;
								};
							}
						}
					} catch (_:Error) {}

					if (game.ui != null && game.ui.mcPopup != null) {
						game.ui.mcPopup.loadMap = function(param1:* = null):* {
							loadVendorMap();
							return null;
						};
					}
				};

				hookPopup();

				// Ensure popup is hooked even if ui.mcPopup is instantiated later
				var onFrame:Function = function(e:Event):void {
					if (game.ui != null && game.ui.mcPopup != null) {
						hookPopup();
						if (game.removeEventListener != null) {
							game.removeEventListener(Event.ENTER_FRAME, onFrame);
						}
					}
				};
				if (game.addEventListener != null) {
					game.addEventListener(Event.ENTER_FRAME, onFrame);
				}

				// Hook game.onTravelMapComplete
				if ("onTravelMapComplete" in game) {
					var origTravelComplete:Function = game.onTravelMapComplete;
					game.onTravelMapComplete = function(param1:Event):void {
						try {
							var str:String = String(param1.target.data);
							var data:Object = JSON.parse(str);
							game.travelMapData = data;
							try {
								var wmClass:Class = ApplicationDomain.currentDomain.getDefinition("worldMap") as Class;
								if (wmClass != null) {
									game.WorldMapData = new wmClass(game.travelMapData);
								}
							} catch (_:Error) {}
							game.TRAVEL_DATA_READY = true;
							if (game.travelLoaderMC != null && game.travelLoaderMC.parent != null) {
								game.travelLoaderMC.parent.removeChild(game.travelLoaderMC);
								game.travelLoaderMC = null;
							}
							loadVendorMap();
						} catch (err:Error) {
							trace("[Mod] Error in hooked onTravelMapComplete: " + err);
							if (origTravelComplete != null) {
								origTravelComplete(param1);
							}
						}
					};
				}
			} catch (e:Error) {
				trace("[Mod] Error in setupMapOverride: " + e);
			}
		}

	}

}
