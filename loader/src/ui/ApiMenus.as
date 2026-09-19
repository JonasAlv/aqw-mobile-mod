package ui {
	import flash.events.Event;
	import flash.events.MouseEvent;
	import flash.display.Sprite;
	import flash.text.TextField;
	import flash.text.TextFieldType;
	import flash.text.TextFormat;
	import flash.utils.setTimeout;
import ui.option.Dropdown;
	import flash.text.TextFormatAlign;
	import ui.Overlay;
	import ui.option.Menu;
	import ui.option.Option;
	import ui.option.Button;
	import ui.option.Check;
	import com.aqwapi.modules.ScriptManager;
	import com.aqwapi.modules.CombatManager;
	import com.aqwapi.AqwApi;
	import com.aqwapi.events.ApiEvent;
	import util.HelperSetting;
	
	POCKET::IS_DESKTOP { 
		import flash.filesystem.File; 
		import flash.filesystem.FileStream; 
		import flash.filesystem.FileMode; 
		import flash.net.FileFilter; 
	}

	public class ApiMenus {
		private static var _injected:Boolean = false;
		private static var _overlay:Overlay;
		private static var _promptContainer:Sprite;
		private static var _promptInput:TextField;
		private static var _lastQuests:String = "";
		private static var _lastCombat:String = "";
		
		public static var anthonyMenus:Vector.<Menu>;
		public static var apiMenus:Vector.<Menu>;
		public static var lastSelectedMenu:Menu = null;
		
		public static function inject(overlay:Overlay):void {
			if (_injected) return;
			_injected = true;
			_overlay = overlay;
			
			var pocket:Pocket = Pocket.SINGLETON ? Pocket.SINGLETON : (overlay.parent as Pocket);

			anthonyMenus = overlay.menus;

			var apiNotifications:Sprite = new Sprite();
			overlay.addChild(apiNotifications);
			ApiNotificationManager.instance.init(apiNotifications);

				CombatManager.farmClass = HelperSetting.getString("api_farm_class", "");
				CombatManager.farmMode = HelperSetting.getString("api_farm_mode", "Base");
				CombatManager.soloClass = HelperSetting.getString("api_solo_class", "");
				CombatManager.soloMode = HelperSetting.getString("api_solo_mode", "Base");

				if (AqwApi.combat != null) {
					AqwApi.combat.infiniteRange = HelperSetting.getBool("api_infinite_range", false);
				}
				if (AqwApi.map != null) {
					AqwApi.map.autoDeathSpawn = HelperSetting.getBool("api_death_spawn", false);
					AqwApi.map.usePrivateRoom = HelperSetting.getBool("api_private_rooms", true);
				}


			var scriptsOpts:Vector.<Option> = new <Option>[
				new Button(null, "Paste Script", "Paste a raw text script.", "Paste", function(o:Option):void { pocket.overlay.gotoAndStop("Init"); showPastePrompt(pocket); })
			];
			
			POCKET::IS_DESKTOP {
				scriptsOpts.push(new Button(null, "Load Script (File)", "Load a script from a text file.", "Load", function(o:Option):void {
					var file:* = File.desktopDirectory;
					file.addEventListener(flash.events.Event.SELECT, function(ev:flash.events.Event):void {
						var stream:* = new FileStream();
						stream.open(file, FileMode.READ);
						var txt:String = stream.readUTFBytes(stream.bytesAvailable);
						stream.close();
						ScriptManager.SINGLETON.loadScript(txt);
						ApiNotificationManager.notify("Script loaded successfully!");
					});
					file.browseForOpen("Select Script", [new FileFilter("Script Files (*.txt, *.hscript, *.hx)", "*.txt;*.hscript;*.hx"), new FileFilter("All Files (*.*)", "*.*")]);
				}));

			}
			
			var startScriptCheck:Check = new Check(null, false, "Run Script", "Start or Stop the loaded script.", true, function(o:Option):void {
				var c:Check = o as Check;
				if (c.state) {
					ScriptManager.SINGLETON.reset();
					ScriptManager.SINGLETON.start();
				} else {
					ScriptManager.SINGLETON.stop();
				}
			});
			startScriptCheck.addEventListener(Event.ENTER_FRAME, function(e:Event):void {
				if (startScriptCheck.state != ScriptManager.SINGLETON.isRunning) {
					startScriptCheck.state = ScriptManager.SINGLETON.isRunning;
					startScriptCheck.syncState();
				}
			});
			scriptsOpts.push(startScriptCheck);

			var chatLogCheck:Check = new Check(null, AqwApi.logger.printToChat, "Chat Logger", "Display bot and script logs in the in-game chat box.", true, function(o:Option):void {
				var c:Check = o as Check;
				AqwApi.logger.printToChat = c.state;
			});
			scriptsOpts.push(chatLogCheck);


			var combatSetupBtn:Button = new Button(null, "AutoCombat (Setup)", "Configure class and mode for smart combat.", "Setup", function(o:Option):void {
				showSmartCombatPrompt(pocket);
			});
			var loadoutsBtn:Button = new Button(null, "Class Loadouts", "Configure your default Farm, Solo, Boss and Dodge classes for script auto-swapping.", "Setup", function(o:Option):void {
				showLoadoutsPrompt(pocket);
			});
			scriptsOpts.push(loadoutsBtn);

			var smartCombatCheck:Check = new Check(null, false, "AutoCombat (Smart)", "Start smart auto combat.", true, function(o:Option):void { 
				var c:Check = o as Check;
				if (c.state) {
					var confClass:String = HelperSetting.getString("api_smart_class", "");
					var confMode:String = HelperSetting.getString("api_smart_mode", "Base");
					if (confClass != "" && AqwApi.inventory) {
						AqwApi.inventory.equip(confClass);
					}
					AqwApi.combat.mode = confMode;
					AqwApi.combat.startSmart(); 
				} else {
					AqwApi.combat.stopAuto();
				}
			});
			smartCombatCheck.addEventListener(Event.ENTER_FRAME, function(e:Event):void {
				if (AqwApi.combat != null && smartCombatCheck.state != AqwApi.combat.isSmartRunning) {
					smartCombatCheck.state = AqwApi.combat.isSmartRunning;
					smartCombatCheck.syncState();
				}
			});

			var customCombatCheck:Check = new Check(null, false, "AutoCombat (Custom)", "Start custom combat sequence.", true, function(o:Option):void { 
				var c:Check = o as Check;
				if (c.state) {
					pocket.overlay.gotoAndStop("Init");
					showCombatPrompt(pocket); 
				} else {
					AqwApi.combat.stopAuto();
				}
			});
			customCombatCheck.addEventListener(Event.ENTER_FRAME, function(e:Event):void {
				if (AqwApi.combat != null && customCombatCheck.state != AqwApi.combat.isCustomRunning) {
					customCombatCheck.state = AqwApi.combat.isCustomRunning;
					customCombatCheck.syncState();
				}
			});

			var autoQuestCheck:Check = new Check(null, false, "Auto Quest", "Start accepting and completing quests.", true, function(o:Option):void { 
				var c:Check = o as Check;
				if (c.state) {
					pocket.overlay.gotoAndStop("Init");
					showQuestPrompt(pocket); 
				} else {
					AqwApi.quest.stopAuto();
				}
			});
			autoQuestCheck.addEventListener(Event.ENTER_FRAME, function(e:Event):void {
				if (AqwApi.quest != null && autoQuestCheck.state != AqwApi.quest.isAutoRunning) {
					autoQuestCheck.state = AqwApi.quest.isAutoRunning;
					autoQuestCheck.syncState();
				}
			});

			var autoLevelingCheck:Check = new Check(null, false, "Auto Leveling", "Auto grind XP in shadowbattleon.", true, function(o:Option):void {
				var c:Check = o as Check;
				if (c.state) {
					var script:String = "EQUIPCLASS farm\nLOADQUEST 9421,9422,9423\nJOIN shadowbattleon,Enter,Spawn\nAUTOQUEST 9421,9422,9423\nEQUIPCLASS farm\nCOMBAT smart\n";
					ScriptManager.SINGLETON.reset();
					ScriptManager.SINGLETON.loadScript(script);
					ScriptManager.SINGLETON.start();
				} else {
					ScriptManager.SINGLETON.stop();
				}
			});
			autoLevelingCheck.addEventListener(Event.ENTER_FRAME, function(e:Event):void {
				if (autoLevelingCheck.state != ScriptManager.SINGLETON.isRunning) {
					autoLevelingCheck.state = ScriptManager.SINGLETON.isRunning;
					autoLevelingCheck.syncState();
				}
			});

			
				var lvl50Shops:Array = [
					{ name: "Healer Enh", id: 762 },
					{ name: "Lucky Enh", id: 763 },
					{ name: "Spellbreaker Enh", id: 764 },
					{ name: "Wizard Enh", id: 765 },
					{ name: "Hybrid Enh", id: 766 },
					{ name: "Thief Enh", id: 767 },
					{ name: "Fighter Enh", id: 768 }
				];
				var aweShops:Array = [
					{ name: "Fighter Awe", id: 635 },
					{ name: "Wizard Awe", id: 636 },
					{ name: "Thief Awe", id: 637 },
					{ name: "Healer Awe", id: 638 },
					{ name: "Lucky Awe", id: 639 },
					{ name: "Hybrid Awe", id: 633 }
				];
				var forgeShops:Array = [
					{ name: "Weapon Enh", id: 2142 },
					{ name: "Cape Enh", id: 2143 },
					{ name: "Helmet Enh", id: 2164 }
				];
				
				var enhOpts:Vector.<Option> = new <Option>[
					new Button(null, "Lvl 50+ Enhancements", "Load level 50+ normal enhancements.", "Open", function(o:Option):void { pocket.overlay.gotoAndStop("Init"); showEnhancementPrompt(pocket, "Lvl 50+ Enhancements", lvl50Shops, false); }),
					new Button(null, "Awe Enhancements", "Load Awe enhancements.", "Open", function(o:Option):void { pocket.overlay.gotoAndStop("Init"); showEnhancementPrompt(pocket, "Awe Enhancements", aweShops, false); }),
					new Button(null, "Forge Enhancements", "Load Forge enhancements (auto-joins /forge).", "Open", function(o:Option):void { pocket.overlay.gotoAndStop("Init"); showEnhancementPrompt(pocket, "Forge Enhancements", forgeShops, true); })
				];

				apiMenus = new <Menu>[
					new Menu("Scripts", scriptsOpts),
					new Menu("Automation", new <Option>[
						combatSetupBtn,
						smartCombatCheck,
						customCombatCheck,
						autoQuestCheck,
						autoLevelingCheck
					]),
					new Menu("Enhancements", enhOpts),

				new Menu("Settings", new <Option>[
					new Button(null, "Load Shop", "Load a shop by its ID.", "Load", function(o:Option):void { pocket.overlay.gotoAndStop("Init"); showShopPrompt(pocket); }),
					new Button(null, "Toggle Bank", "Open or close your bank.", "Toggle", function(o:Option):void { AqwApi.inventory.toggleBank(); }),
					new Check("api_infinite_range", false, "Infinite Range", "Attack and use skills across the entire screen without range limits.", true, function(o:Option):void {
						var c:Check = o as Check;
						if (AqwApi.combat != null) {
							AqwApi.combat.infiniteRange = c.state;
							if (c.state) AqwApi.combat.applyInfiniteRange();
						}
					}),
					new Check("api_death_spawn", false, "Death Spawn (Same Room)", "Automatically sets your respawn point to your current room so you never walk back on death.", true, function(o:Option):void {
						var c:Check = o as Check;
						if (AqwApi.map != null) AqwApi.map.autoDeathSpawn = c.state;
					}),
					new Check("api_private_rooms", true, "Private Rooms", "Automatically join private rooms (e.g. map-100000). Uncheck to join public rooms.", true, function(o:Option):void {
						var c:Check = o as Check;
						if (AqwApi.map != null) AqwApi.map.usePrivateRoom = c.state;
					}),
					new Check("api_accept_loot", false, "Accept All Loot", "Automatically accept all dropped items.", true, function(o:Option):void {
						var c:Check = o as Check;
						if (AqwApi.drop != null) AqwApi.drop.acceptAll = c.state;
					}),
					new Check("api_accept_ac_drops", false, "Accept AC Drops", "Automatically accept all AC-tagged (coin) drops.", true, function(o:Option):void {
						var c:Check = o as Check;
						if (AqwApi.drop != null) AqwApi.drop.acceptACs = c.state;
					}),
					new Check(HelperSetting.OPTION_SWF_CACHE, false, "SWF RAM Cache", "Caches loaded maps and classes to RAM to eliminate reloading. (Requires more RAM)", true, function(o:Option):void {
						Pocket.SINGLETON.config.option_swf_cache = Check(o).state;
					})
				])
			];

			// Fix for timeline button recreation bug using Event Delegation
			overlay.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				if (overlay.currentFrameLabel == "Init" && overlay.showPanelBtn != null) {
					var isShowPanelBtn:Boolean = false;
					var curr:* = e.target;
					while (curr != null && curr != overlay) {
						if (curr == overlay.showPanelBtn) {
							isShowPanelBtn = true;
							break;
						}
						curr = curr.parent;
					}
					if (isShowPanelBtn) {
						overlay.menus = anthonyMenus;
						lastSelectedMenu = null;
					}
				}
			}, true); // Capture phase guarantees it runs before native handlers!

			var initialLootState:Boolean = HelperSetting.getBool("api_accept_loot", false);
			if (AqwApi.drop != null) AqwApi.drop.acceptAll = initialLootState;

			var initialACState:Boolean = HelperSetting.getBool("api_accept_ac_drops", false);
			if (AqwApi.drop != null) AqwApi.drop.acceptACs = initialACState;

			var icon:Sprite = new Sprite();
			icon.graphics.beginFill(0x990000, 0.95);
			icon.graphics.lineStyle(1, 0x660000);
			icon.graphics.drawRoundRect(0, 0, 80, 35, 8, 8); 
			icon.graphics.endFill();
			
			var txt:TextField = new TextField();
			txt.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF, true, null, null, null, null, TextFormatAlign.CENTER);
			txt.text = "Menu";
			txt.width = 80;
			txt.y = 8;
			txt.selectable = false;
			txt.mouseEnabled = false;
			icon.addChild(txt);
			
			icon.x = 80;
			icon.y = 10;
			icon.buttonMode = true;
			
			var theStage:* = (pocket != null && pocket.stage != null) ? pocket.stage : overlay.stage;
			if (theStage != null) {
				theStage.addChild(icon);
			} else {
				overlay.addEventListener(Event.ADDED_TO_STAGE, function(ev:Event):void {
					overlay.removeEventListener(Event.ADDED_TO_STAGE, arguments.callee);
					if (overlay.stage != null) {
						overlay.stage.addChild(icon);
					}
				});
			}

			var isDragging:Boolean = false;
			var hasDragged:Boolean = false;
			var dragStartX:Number = 0;
			var dragStartY:Number = 0;

			icon.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent):void {
				isDragging = true;
				hasDragged = false;
				dragStartX = e.stageX - icon.x;
				dragStartY = e.stageY - icon.y;
			});

			if (theStage != null) {
				theStage.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent):void {
					if (isDragging) {
						hasDragged = true;
						var nx:Number = e.stageX - dragStartX;
						var ny:Number = e.stageY - dragStartY;
						
						var sw:Number = theStage.stageWidth > 0 ? theStage.stageWidth : 960;
						var sh:Number = theStage.stageHeight > 0 ? theStage.stageHeight : 500;
						
						if (nx < 0) nx = 0;
						if (ny < 0) ny = 0;
						if (nx > sw - 80) nx = sw - 80;
						if (ny > sh - 35) ny = sh - 35;
						
						icon.x = nx;
						icon.y = ny;
					}
				});
				theStage.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent):void {
					isDragging = false;
				});
			}

			icon.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				if (hasDragged) return;
				overlay.menus = apiMenus;
				overlay.gotoAndStop("Panel");
				if (lastSelectedMenu != null && apiMenus.indexOf(lastSelectedMenu) != -1) {
					overlay.selectMenu(lastSelectedMenu);
				}
			});

			overlay.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				if (overlay.currentFrameLabel == "Panel" && overlay.contentMenu != null) {
					var c:* = e.target;
					while (c != null && c != overlay.contentMenu && c != overlay) {
						if (c is Menu) {
							lastSelectedMenu = c as Menu;
							break;
						}
						c = c.parent;
					}
				}
			}, false);
			
			overlay.addEventListener(Event.ENTER_FRAME, function(e:Event):void {
				if (pocket.config.option_disable_cutscenes && pocket.game != null && pocket.game.world != null) {
					if (("mcExtSWF" in pocket.game.world) && pocket.game.world.mcExtSWF != null && pocket.game.world.mcExtSWF.numChildren > 0) {
						var ext:* = pocket.game.world.mcExtSWF.getChildAt(0);
						if (ext != null && "totalFrames" in ext) {
							ext.gotoAndPlay(ext.totalFrames - 2);
							if ("showInterface" in pocket.game.world) {
								pocket.game.world.showInterface();
							}
						}
					}
				}

				var isScriptRunning:Boolean = (ScriptManager.SINGLETON.isRunning);
				var infiniteRangeActive:Boolean = isScriptRunning || HelperSetting.getBool("api_infinite_range", false);
				var deathSpawnActive:Boolean = isScriptRunning || HelperSetting.getBool("api_death_spawn", false);

				if (AqwApi.map != null) {
					AqwApi.map.autoDeathSpawn = deathSpawnActive;
					if (deathSpawnActive) {
						AqwApi.map.checkAutoDeathSpawn();
					}
				}
				if (AqwApi.combat != null) {
					AqwApi.combat.infiniteRange = infiniteRangeActive;
					if (infiniteRangeActive) {
						AqwApi.combat.applyInfiniteRange();
					}
				}

				var isPanelOpen:Boolean = (overlay.currentFrameLabel == "Panel");
				icon.visible = !isPanelOpen;
				
				if (isPanelOpen) {
					for (var i:int = 0; i < overlay.numChildren; i++) {
						var child:* = overlay.getChildAt(i);
						try {
							if (child.hasOwnProperty("text") && child["text"] == "Pocket") {
								child.visible = false;
							}
						} catch(err:*) {}
					}
					
					var isApiMenu:Boolean = (overlay.menus == apiMenus);
					if (overlay.updateBtn != null) overlay.updateBtn.visible = !isApiMenu;
					if (overlay.discordBtn != null) overlay.discordBtn.visible = !isApiMenu;
					if (overlay.reportBugBtn != null) overlay.reportBugBtn.visible = !isApiMenu;
				}
			});
		}

		private static function showQuestPrompt(pocket:*):void {
			hidePrompt();
			_promptContainer = new Sprite();
			_promptContainer.graphics.beginFill(0x121212, 0.95);
			_promptContainer.graphics.lineStyle(1, 0x2A2A2A);
			_promptContainer.graphics.drawRoundRect(0, 0, 300, 160, 8, 8);
			_promptContainer.graphics.endFill();
			_promptContainer.x = (960 - 300) / 2;
			_promptContainer.y = (500 - 160) / 2;
			
			var title:TextField = new TextField();
			title.defaultTextFormat = new TextFormat("_sans", 14, 0xE0E0E0, true, null, null, null, null, TextFormatAlign.CENTER);
			title.text = "Enter Quest IDs (comma separated):";
			title.width = 300;
			title.y = 10;
			title.selectable = false;
			_promptContainer.addChild(title);
			
			_promptInput = new TextField();
			_promptInput.type = TextFieldType.INPUT;
			_promptInput.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF);
			_promptInput.border = true;
			_promptInput.borderColor = 0x555555;
			_promptInput.background = true;
			_promptInput.backgroundColor = 0x222222;
			_promptInput.x = 20;
			_promptInput.y = 40;
			_promptInput.width = 260;
			_promptInput.height = 25;
			_promptInput.text = _lastQuests;
			_promptContainer.addChild(_promptInput);
			
			var startBtn:Sprite = new Sprite();
			startBtn.graphics.beginFill(0x1E1E1E, 1);
			startBtn.graphics.lineStyle(1, 0x3A3A3A);
			startBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5);
			startBtn.graphics.endFill();
			startBtn.x = 20;
			startBtn.y = 80;
			startBtn.buttonMode = true;
			
			var startTxt:TextField = new TextField();
			startTxt.defaultTextFormat = new TextFormat("_sans", 12, 0xCCCCCC, true, null, null, null, null, TextFormatAlign.CENTER);
			startTxt.text = "Start";
			startTxt.width = 120;
			startTxt.y = 5;
			startTxt.selectable = false;
			startTxt.mouseEnabled = false;
			startBtn.addChild(startTxt);
			
			startBtn.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent):void { startBtn.graphics.clear(); startBtn.graphics.beginFill(0x333333, 1); startBtn.graphics.lineStyle(1, 0x555555); startBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); startBtn.graphics.endFill(); startTxt.textColor = 0xFFFFFF; });
			startBtn.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent):void { startBtn.graphics.clear(); startBtn.graphics.beginFill(0x1E1E1E, 1); startBtn.graphics.lineStyle(1, 0x3A3A3A); startBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); startBtn.graphics.endFill(); startTxt.textColor = 0xCCCCCC; });
			
			startBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				_lastQuests = _promptInput.text;
				var ids:Array = _lastQuests.split(",");
				var validIds:Array = [];
				for (var i:int = 0; i < ids.length; i++) {
					var qid:int = parseInt(String(ids[i]).replace(/^\s+|\s+$/g, ""));
					if (qid > 0) validIds.push(qid);
				}
				if (validIds.length > 0) {
					AqwApi.quest.startAuto(validIds.join(","));
				}
				hidePrompt();
			});
			_promptContainer.addChild(startBtn);
			
			var cancelBtn:Sprite = new Sprite();
			cancelBtn.graphics.beginFill(0x1E1E1E, 1);
			cancelBtn.graphics.lineStyle(1, 0x3A3A3A);
			cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5);
			cancelBtn.graphics.endFill();
			cancelBtn.x = 160;
			cancelBtn.y = 80;
			cancelBtn.buttonMode = true;
			
			var cancelTxt:TextField = new TextField();
			cancelTxt.defaultTextFormat = new TextFormat("_sans", 12, 0xCCCCCC, true, null, null, null, null, TextFormatAlign.CENTER);
			cancelTxt.text = "Cancel";
			cancelTxt.width = 120;
			cancelTxt.y = 5;
			cancelTxt.selectable = false;
			cancelTxt.mouseEnabled = false;
			cancelBtn.addChild(cancelTxt);
			
			cancelBtn.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent):void { cancelBtn.graphics.clear(); cancelBtn.graphics.beginFill(0x333333, 1); cancelBtn.graphics.lineStyle(1, 0x555555); cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); cancelBtn.graphics.endFill(); cancelTxt.textColor = 0xFFFFFF; });
			cancelBtn.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent):void { cancelBtn.graphics.clear(); cancelBtn.graphics.beginFill(0x1E1E1E, 1); cancelBtn.graphics.lineStyle(1, 0x3A3A3A); cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); cancelBtn.graphics.endFill(); cancelTxt.textColor = 0xCCCCCC; });
			
			cancelBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				hidePrompt();
			});
			_promptContainer.addChild(cancelBtn);
			
			if (pocket.overlay != null) {
				pocket.overlay.addChild(_promptContainer);
			}
		}

		

		private static var _selectedClassStr:String = "";
		private static var _selectedModeStr:String = "Base";

		
		private static function showLoadoutsPrompt(pocket:*):void {
			hidePrompt();
			_promptContainer = new Sprite();
			_promptContainer.graphics.beginFill(0x121212, 0.95);
			_promptContainer.graphics.lineStyle(1, 0x2A2A2A);
			_promptContainer.graphics.drawRoundRect(0, 0, 420, 390, 8, 8);
			_promptContainer.graphics.endFill();
			_promptContainer.x = (960 - 420) / 2;
			_promptContainer.y = (500 - 390) / 2;
			
			var title:TextField = new TextField();
			title.defaultTextFormat = new TextFormat("_sans", 16, 0xE0E0E0, true, null, null, null, null, TextFormatAlign.CENTER);
			title.text = "Class Loadouts (For Scripts)";
			title.width = 420;
			title.y = 10;
			title.selectable = false;
			title.mouseEnabled = false;
			_promptContainer.addChild(title);

			var availableClasses:Array = [];
			if (AqwApi.game && AqwApi.game.world && AqwApi.game.world.myAvatar && AqwApi.game.world.myAvatar.items) {
				for each (var item:Object in AqwApi.game.world.myAvatar.items) {
					if (item.sES == "ar") availableClasses.push(item.sName);
				}
			}
			if (availableClasses.length == 0) availableClasses.push("No Classes Found");
			
			// FARM ROW
			var lblFarm:TextField = new TextField();
			lblFarm.defaultTextFormat = new TextFormat("_sans", 14, 0xCCCCCC, true);
			lblFarm.text = "FARM Loadout:";
			lblFarm.x = 20; lblFarm.y = 45; lblFarm.width = 150;
			lblFarm.selectable = false;
			_promptContainer.addChild(lblFarm);
			
			var fClass:String = HelperSetting.getString("api_farm_class", availableClasses[0]);
			if (availableClasses.indexOf(fClass) == -1) fClass = availableClasses[0];
			var fModes:Array = CombatManager.getAvailableModes(fClass);
			var fMode:String = HelperSetting.getString("api_farm_mode", fModes[0]);
			if (fModes.indexOf(fMode) == -1) fMode = fModes[0];
			
			var ddFarmMode:Dropdown = new Dropdown(120, 25, fModes, function(sel:String):void {
				fMode = sel; HelperSetting.setString("api_farm_mode", sel); CombatManager.farmMode = sel;
			});
			ddFarmMode.x = 280; ddFarmMode.y = 70;
			
			var ddFarmClass:Dropdown = new Dropdown(240, 25, availableClasses, function(sel:String):void {
				fClass = sel; HelperSetting.setString("api_farm_class", sel); CombatManager.farmClass = sel;
				var nm:Array = CombatManager.getAvailableModes(fClass);
				ddFarmMode.options = nm;
				ddFarmMode.selectedItem = nm[0];
				fMode = nm[0]; HelperSetting.setString("api_farm_mode", fMode); CombatManager.farmMode = fMode;
			});
			ddFarmClass.x = 20; ddFarmClass.y = 70;
			ddFarmClass.selectedItem = fClass;
			ddFarmMode.selectedItem = fMode;
			_promptContainer.addChild(ddFarmMode);
			_promptContainer.addChild(ddFarmClass);
			
			// SOLO ROW
			var lblSolo:TextField = new TextField();
			lblSolo.defaultTextFormat = new TextFormat("_sans", 14, 0xCCCCCC, true);
			lblSolo.text = "SOLO Loadout:";
			lblSolo.x = 20; lblSolo.y = 110; lblSolo.width = 150;
			lblSolo.selectable = false;
			_promptContainer.addChild(lblSolo);
			
			var sClass:String = HelperSetting.getString("api_solo_class", availableClasses[0]);
			if (availableClasses.indexOf(sClass) == -1) sClass = availableClasses[0];
			var sModes:Array = CombatManager.getAvailableModes(sClass);
			var sMode:String = HelperSetting.getString("api_solo_mode", sModes[0]);
			if (sModes.indexOf(sMode) == -1) sMode = sModes[0];
			
			var ddSoloMode:Dropdown = new Dropdown(120, 25, sModes, function(sel:String):void {
				sMode = sel; HelperSetting.setString("api_solo_mode", sel); CombatManager.soloMode = sel;
			});
			ddSoloMode.x = 280; ddSoloMode.y = 135;
			
			var ddSoloClass:Dropdown = new Dropdown(240, 25, availableClasses, function(sel:String):void {
				sClass = sel; HelperSetting.setString("api_solo_class", sel); CombatManager.soloClass = sel;
				var nm:Array = CombatManager.getAvailableModes(sClass);
				ddSoloMode.options = nm;
				ddSoloMode.selectedItem = nm[0];
				sMode = nm[0]; HelperSetting.setString("api_solo_mode", sMode); CombatManager.soloMode = sMode;
			});
			ddSoloClass.x = 20; ddSoloClass.y = 135;
			ddSoloClass.selectedItem = sClass;
			ddSoloMode.selectedItem = sMode;
			_promptContainer.addChild(ddSoloMode);
			_promptContainer.addChild(ddSoloClass);

			// BOSS ROW
			var lblBoss:TextField = new TextField();
			lblBoss.defaultTextFormat = new TextFormat("_sans", 14, 0xCCCCCC, true);
			lblBoss.text = "BOSS Loadout:";
			lblBoss.x = 20; lblBoss.y = 175; lblBoss.width = 150;
			lblBoss.selectable = false;
			_promptContainer.addChild(lblBoss);
			
			var bClass:String = HelperSetting.getString("api_boss_class", availableClasses[0]);
			if (availableClasses.indexOf(bClass) == -1) bClass = availableClasses[0];
			var bModes:Array = CombatManager.getAvailableModes(bClass);
			var bMode:String = HelperSetting.getString("api_boss_mode", bModes[0]);
			if (bModes.indexOf(bMode) == -1) bMode = bModes[0];
			
			var ddBossMode:Dropdown = new Dropdown(120, 25, bModes, function(sel:String):void {
				bMode = sel; HelperSetting.setString("api_boss_mode", sel); CombatManager.bossMode = sel;
			});
			ddBossMode.x = 280; ddBossMode.y = 200;
			
			var ddBossClass:Dropdown = new Dropdown(240, 25, availableClasses, function(sel:String):void {
				bClass = sel; HelperSetting.setString("api_boss_class", sel); CombatManager.bossClass = sel;
				var nm:Array = CombatManager.getAvailableModes(bClass);
				ddBossMode.options = nm;
				ddBossMode.selectedItem = nm[0];
				bMode = nm[0]; HelperSetting.setString("api_boss_mode", bMode); CombatManager.bossMode = bMode;
			});
			ddBossClass.x = 20; ddBossClass.y = 200;
			ddBossClass.selectedItem = bClass;
			ddBossMode.selectedItem = bMode;
			_promptContainer.addChild(ddBossMode);
			_promptContainer.addChild(ddBossClass);

			// DODGE ROW
			var lblDodge:TextField = new TextField();
			lblDodge.defaultTextFormat = new TextFormat("_sans", 14, 0xCCCCCC, true);
			lblDodge.text = "DODGE Loadout:";
			lblDodge.x = 20; lblDodge.y = 240; lblDodge.width = 150;
			lblDodge.selectable = false;
			_promptContainer.addChild(lblDodge);
			
			var dClass:String = HelperSetting.getString("api_dodge_class", availableClasses[0]);
			if (availableClasses.indexOf(dClass) == -1) dClass = availableClasses[0];
			var dModes:Array = CombatManager.getAvailableModes(dClass);
			var dMode:String = HelperSetting.getString("api_dodge_mode", dModes[0]);
			if (dModes.indexOf(dMode) == -1) dMode = dModes[0];
			
			var ddDodgeMode:Dropdown = new Dropdown(120, 25, dModes, function(sel:String):void {
				dMode = sel; HelperSetting.setString("api_dodge_mode", sel); CombatManager.dodgeMode = sel;
			});
			ddDodgeMode.x = 280; ddDodgeMode.y = 265;
			
			var ddDodgeClass:Dropdown = new Dropdown(240, 25, availableClasses, function(sel:String):void {
				dClass = sel; HelperSetting.setString("api_dodge_class", sel); CombatManager.dodgeClass = sel;
				var nm:Array = CombatManager.getAvailableModes(dClass);
				ddDodgeMode.options = nm;
				ddDodgeMode.selectedItem = nm[0];
				dMode = nm[0]; HelperSetting.setString("api_dodge_mode", dMode); CombatManager.dodgeMode = dMode;
			});
			ddDodgeClass.x = 20; ddDodgeClass.y = 265;
			ddDodgeClass.selectedItem = dClass;
			ddDodgeMode.selectedItem = dMode;
			_promptContainer.addChild(ddDodgeMode);
			_promptContainer.addChild(ddDodgeClass);

			// CLOSE BTN
			var closeBtn:Sprite = new Sprite();
			closeBtn.graphics.beginFill(0x1E1E1E, 1);
			closeBtn.graphics.lineStyle(1, 0x3A3A3A);
			closeBtn.graphics.drawRoundRect(0, 0, 150, 35, 5, 5);
			closeBtn.graphics.endFill();
			closeBtn.x = 135;
			closeBtn.y = 330;
			closeBtn.buttonMode = true;
			var closeTxt:TextField = new TextField();
			closeTxt.defaultTextFormat = new TextFormat("_sans", 14, 0xCCCCCC, true, null, null, null, null, TextFormatAlign.CENTER);
			closeTxt.text = "Save & Close";
			closeTxt.width = 150; closeTxt.y = 8;
			closeTxt.selectable = false; closeTxt.mouseEnabled = false;
			closeBtn.addChild(closeTxt);
			closeBtn.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent):void { closeBtn.graphics.clear(); closeBtn.graphics.beginFill(0x333333, 1); closeBtn.graphics.lineStyle(1, 0x555555); closeBtn.graphics.drawRoundRect(0, 0, 150, 35, 5, 5); closeBtn.graphics.endFill(); closeTxt.textColor = 0xFFFFFF; });
			closeBtn.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent):void { closeBtn.graphics.clear(); closeBtn.graphics.beginFill(0x1E1E1E, 1); closeBtn.graphics.lineStyle(1, 0x3A3A3A); closeBtn.graphics.drawRoundRect(0, 0, 150, 35, 5, 5); closeBtn.graphics.endFill(); closeTxt.textColor = 0xCCCCCC; });
			closeBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void { hidePrompt(); });
			_promptContainer.addChild(closeBtn);
			
			pocket.overlay.addChild(_promptContainer);
		}


		private static function showSmartCombatPrompt(pocket:*):void {
			hidePrompt();
			_promptContainer = new Sprite();
			_promptContainer.graphics.beginFill(0x121212, 0.95);
			_promptContainer.graphics.lineStyle(1, 0x2A2A2A);
			_promptContainer.graphics.drawRoundRect(0, 0, 400, 250, 8, 8);
			_promptContainer.graphics.endFill();
			_promptContainer.x = (960 - 400) / 2;
			_promptContainer.y = (500 - 250) / 2;
			
			var title:TextField = new TextField();
			title.defaultTextFormat = new TextFormat("_sans", 16, 0xE0E0E0, true, null, null, null, null, TextFormatAlign.CENTER);
			title.text = "AutoCombat Setup";
			title.width = 400;
			title.y = 10;
			title.selectable = false;
			title.mouseEnabled = false;
			_promptContainer.addChild(title);
			
			var lblClass:TextField = new TextField();
			lblClass.defaultTextFormat = new TextFormat("_sans", 14, 0xCCCCCC);
			lblClass.text = "Class:";
			lblClass.x = 20;
			lblClass.y = 50;
			lblClass.width = 60;
			lblClass.selectable = false;
			_promptContainer.addChild(lblClass);
			
			var lblMode:TextField = new TextField();
			lblMode.defaultTextFormat = new TextFormat("_sans", 14, 0xCCCCCC);
			lblMode.text = "Mode:";
			lblMode.x = 220;
			lblMode.y = 50;
			lblMode.width = 60;
			lblMode.selectable = false;
			_promptContainer.addChild(lblMode);
			
			var availableClasses:Array = [];
			var currentClass:String = "";
			if (AqwApi.game && AqwApi.game.world && AqwApi.game.world.myAvatar) {
				if (AqwApi.game.world.myAvatar.objData) {
					currentClass = String(AqwApi.game.world.myAvatar.objData.strClassName);
				}
				if (AqwApi.game.world.myAvatar.items) {
						for each (var item:Object in AqwApi.game.world.myAvatar.items) {
							if (item.sES == "ar") {
								availableClasses.push(item.sName);
							}
					}
				}
			}
			if (availableClasses.length == 0) availableClasses.push("No Classes Found");
			
			_selectedClassStr = HelperSetting.getString("api_smart_class", currentClass != "" ? currentClass : availableClasses[0]);
			if (availableClasses.indexOf(_selectedClassStr) == -1) {
				_selectedClassStr = currentClass != "" ? currentClass : availableClasses[0];
			}
			
			var availableModes:Array = CombatManager.getAvailableModes(_selectedClassStr);
			_selectedModeStr = HelperSetting.getString("api_smart_mode", "Base");
			if (availableModes.indexOf(_selectedModeStr) == -1) {
				_selectedModeStr = availableModes[0];
			}
			
			var ddMode:Dropdown = new Dropdown(150, 25, availableModes, function(sel:String):void {
				_selectedModeStr = sel;
			});
			ddMode.x = 220;
			ddMode.y = 70;
			
			var ddClass:Dropdown = new Dropdown(180, 25, availableClasses, function(sel:String):void {
				_selectedClassStr = sel;
				var newModes:Array = CombatManager.getAvailableModes(_selectedClassStr);
				ddMode.options = newModes;
				_selectedModeStr = ddMode.selectedItem;
			});
			ddClass.x = 20;
			ddClass.y = 70;
			ddClass.selectedItem = _selectedClassStr;
			ddMode.selectedItem = _selectedModeStr;
			
			_promptContainer.addChild(ddMode);
			_promptContainer.addChild(ddClass);
			
			var startBtn:Sprite = new Sprite();
			startBtn.graphics.beginFill(0x990000, 1);
			startBtn.graphics.lineStyle(1, 0xCC0000);
			startBtn.graphics.drawRoundRect(0, 0, 150, 35, 5, 5);
			startBtn.graphics.endFill();
			startBtn.x = 20;
			startBtn.y = 190;
			startBtn.buttonMode = true;
			
			var startTxt:TextField = new TextField();
			startTxt.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF, true, null, null, null, null, TextFormatAlign.CENTER);
			startTxt.text = "Save Configuration";
			startTxt.width = 150;
			startTxt.y = 8;
			startTxt.selectable = false;
			startTxt.mouseEnabled = false;
			startBtn.addChild(startTxt);
			
			startBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				HelperSetting.setString("api_smart_class", _selectedClassStr);
				HelperSetting.setString("api_smart_mode", _selectedModeStr);
				ApiNotificationManager.notify("Smart Combat Configuration Saved!");
				hidePrompt();
			});
			_promptContainer.addChild(startBtn);
			
			var cancelBtn:Sprite = new Sprite();
			cancelBtn.graphics.beginFill(0x1E1E1E, 1);
			cancelBtn.graphics.lineStyle(1, 0x3A3A3A);
			cancelBtn.graphics.drawRoundRect(0, 0, 100, 35, 5, 5);
			cancelBtn.graphics.endFill();
			cancelBtn.x = 280;
			cancelBtn.y = 190;
			cancelBtn.buttonMode = true;
			
			var cancelTxt:TextField = new TextField();
			cancelTxt.defaultTextFormat = new TextFormat("_sans", 14, 0xCCCCCC, true, null, null, null, null, TextFormatAlign.CENTER);
			cancelTxt.text = "Cancel";
			cancelTxt.width = 100;
			cancelTxt.y = 8;
			cancelTxt.selectable = false;
			cancelTxt.mouseEnabled = false;
			cancelBtn.addChild(cancelTxt);
			
			cancelBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				hidePrompt();
			});
			_promptContainer.addChild(cancelBtn);
			
			if (pocket.overlay != null) {
				pocket.overlay.addChild(_promptContainer);
			}
		}

		private static function showCombatPrompt(pocket:*):void {
			hidePrompt();
			_promptContainer = new Sprite();
			_promptContainer.graphics.beginFill(0x121212, 0.95);
			_promptContainer.graphics.lineStyle(1, 0x2A2A2A);
			_promptContainer.graphics.drawRoundRect(0, 0, 300, 160, 8, 8);
			_promptContainer.graphics.endFill();
			_promptContainer.x = (960 - 300) / 2;
			_promptContainer.y = (500 - 160) / 2;
			
			var title:TextField = new TextField();
			title.defaultTextFormat = new TextFormat("_sans", 14, 0xE0E0E0, true, null, null, null, null, TextFormatAlign.CENTER);
			title.text = "Enter Skills (e.g. 1,2,3,4):";
			title.width = 300;
			title.y = 10;
			title.selectable = false;
			_promptContainer.addChild(title);
			
			_promptInput = new TextField();
			_promptInput.type = TextFieldType.INPUT;
			_promptInput.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF);
			_promptInput.border = true;
			_promptInput.borderColor = 0x555555;
			_promptInput.background = true;
			_promptInput.backgroundColor = 0x222222;
			_promptInput.x = 20;
			_promptInput.y = 40;
			_promptInput.width = 260;
			_promptInput.height = 25;
			_promptInput.text = _lastCombat;
			_promptContainer.addChild(_promptInput);
			
			var startBtn:Sprite = new Sprite();
			startBtn.graphics.beginFill(0x1E1E1E, 1);
			startBtn.graphics.lineStyle(1, 0x3A3A3A);
			startBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5);
			startBtn.graphics.endFill();
			startBtn.x = 20;
			startBtn.y = 80;
			startBtn.buttonMode = true;
			
			var startTxt:TextField = new TextField();
			startTxt.defaultTextFormat = new TextFormat("_sans", 12, 0xCCCCCC, true, null, null, null, null, TextFormatAlign.CENTER);
			startTxt.text = "Start";
			startTxt.width = 120;
			startTxt.y = 5;
			startTxt.selectable = false;
			startTxt.mouseEnabled = false;
			startBtn.addChild(startTxt);
			
			startBtn.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent):void { startBtn.graphics.clear(); startBtn.graphics.beginFill(0x333333, 1); startBtn.graphics.lineStyle(1, 0x555555); startBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); startBtn.graphics.endFill(); startTxt.textColor = 0xFFFFFF; });
			startBtn.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent):void { startBtn.graphics.clear(); startBtn.graphics.beginFill(0x1E1E1E, 1); startBtn.graphics.lineStyle(1, 0x3A3A3A); startBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); startBtn.graphics.endFill(); startTxt.textColor = 0xCCCCCC; });
			
			startBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				_lastCombat = _promptInput.text;
				var seq:Array = _lastCombat.split(",");
				var validSeq:Array = [];
				for (var i:int = 0; i < seq.length; i++) {
					var sid:String = String(seq[i]).replace(/^\s+|\s+$/g, "");
					if (sid.length > 0) validSeq.push(sid);
				}
				if (validSeq.length > 0) {
					AqwApi.combat.startCustom(validSeq.join(","));
				}
				hidePrompt();
			});
			_promptContainer.addChild(startBtn);
			
			var cancelBtn:Sprite = new Sprite();
			cancelBtn.graphics.beginFill(0x1E1E1E, 1);
			cancelBtn.graphics.lineStyle(1, 0x3A3A3A);
			cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5);
			cancelBtn.graphics.endFill();
			cancelBtn.x = 160;
			cancelBtn.y = 80;
			cancelBtn.buttonMode = true;
			
			var cancelTxt:TextField = new TextField();
			cancelTxt.defaultTextFormat = new TextFormat("_sans", 12, 0xCCCCCC, true, null, null, null, null, TextFormatAlign.CENTER);
			cancelTxt.text = "Cancel";
			cancelTxt.width = 120;
			cancelTxt.y = 5;
			cancelTxt.selectable = false;
			cancelTxt.mouseEnabled = false;
			cancelBtn.addChild(cancelTxt);
			
			cancelBtn.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent):void { cancelBtn.graphics.clear(); cancelBtn.graphics.beginFill(0x333333, 1); cancelBtn.graphics.lineStyle(1, 0x555555); cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); cancelBtn.graphics.endFill(); cancelTxt.textColor = 0xFFFFFF; });
			cancelBtn.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent):void { cancelBtn.graphics.clear(); cancelBtn.graphics.beginFill(0x1E1E1E, 1); cancelBtn.graphics.lineStyle(1, 0x3A3A3A); cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); cancelBtn.graphics.endFill(); cancelTxt.textColor = 0xCCCCCC; });
			
			cancelBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				hidePrompt();
			});
			_promptContainer.addChild(cancelBtn);
			
			if (pocket.overlay != null) {
				pocket.overlay.addChild(_promptContainer);
			}
		}

		
		private static function showEnhancementPrompt(pocket:*, promptTitle:String, shops:Array, requireForge:Boolean = false):void {
			hidePrompt();
			_promptContainer = new Sprite();
			_promptContainer.graphics.beginFill(0x121212, 0.95);
			_promptContainer.graphics.lineStyle(1, 0x2A2A2A);
			_promptContainer.graphics.drawRoundRect(0, 0, 340, 180, 8, 8);
			_promptContainer.graphics.endFill();
			_promptContainer.x = (960 - 340) / 2;
			_promptContainer.y = (500 - 180) / 2;
			
			var title:TextField = new TextField();
			title.defaultTextFormat = new TextFormat("_sans", 16, 0xE0E0E0, true, null, null, null, null, TextFormatAlign.CENTER);
			title.text = promptTitle;
			title.width = 340;
			title.y = 15;
			title.selectable = false;
			title.mouseEnabled = false;
			_promptContainer.addChild(title);
			
			var shopNames:Array = [];
			for (var i:int = 0; i < shops.length; i++) {
				shopNames.push(shops[i].name);
			}
			
			var selectedId:int = shops[0].id;
			var selectedName:String = shops[0].name;
			
			var ddShop:Dropdown = new Dropdown(260, 30, shopNames, function(sel:String):void {
				selectedName = sel;
				for (var j:int = 0; j < shops.length; j++) {
					if (shops[j].name == sel) {
						selectedId = shops[j].id;
						break;
					}
				}
			});
			ddShop.x = 40;
			ddShop.y = 55;
			_promptContainer.addChild(ddShop);
			
			var loadBtn:Sprite = new Sprite();
			loadBtn.graphics.beginFill(0x990000, 1);
			loadBtn.graphics.lineStyle(1, 0xCC0000);
			loadBtn.graphics.drawRoundRect(0, 0, 120, 35, 5, 5);
			loadBtn.graphics.endFill();
			loadBtn.x = 40;
			loadBtn.y = 120;
			loadBtn.buttonMode = true;
			
			var loadTxt:TextField = new TextField();
			loadTxt.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF, true, null, null, null, null, TextFormatAlign.CENTER);
			loadTxt.text = "Load Shop";
			loadTxt.width = 120;
			loadTxt.y = 8;
			loadTxt.selectable = false;
			loadTxt.mouseEnabled = false;
			loadBtn.addChild(loadTxt);
			
			loadBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				hidePrompt();
				if (requireForge) {
					if (AqwApi.map != null && AqwApi.map.name != null && AqwApi.map.name.toLowerCase() != "forge") {
						AqwApi.map.join("forge", "Enter", "Spawn");
						ApiNotificationManager.notify("Joining forge map...");
						setTimeout(function():void {
							AqwApi.shop.loadShop(selectedId);
							ApiNotificationManager.notify("Loading Shop: " + selectedName);
						}, 3500);
					} else {
						AqwApi.shop.loadShop(selectedId);
						ApiNotificationManager.notify("Loading Shop: " + selectedName);
					}
				} else {
					AqwApi.shop.loadShop(selectedId);
					ApiNotificationManager.notify("Loading Shop: " + selectedName);
				}
			});
			_promptContainer.addChild(loadBtn);
			
			var cancelBtn:Sprite = new Sprite();
			cancelBtn.graphics.beginFill(0x1E1E1E, 1);
			cancelBtn.graphics.lineStyle(1, 0x3A3A3A);
			cancelBtn.graphics.drawRoundRect(0, 0, 100, 35, 5, 5);
			cancelBtn.graphics.endFill();
			cancelBtn.x = 180;
			cancelBtn.y = 120;
			cancelBtn.buttonMode = true;
			
			var cancelTxt:TextField = new TextField();
			cancelTxt.defaultTextFormat = new TextFormat("_sans", 14, 0xCCCCCC, true, null, null, null, null, TextFormatAlign.CENTER);
			cancelTxt.text = "Cancel";
			cancelTxt.width = 100;
			cancelTxt.y = 8;
			cancelTxt.selectable = false;
			cancelTxt.mouseEnabled = false;
			cancelBtn.addChild(cancelTxt);
			
			cancelBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				hidePrompt();
			});
			_promptContainer.addChild(cancelBtn);
			
			if (pocket.overlay != null) {
				pocket.overlay.addChild(_promptContainer);
			}
		}

		private static function showShopPrompt(pocket:*):void {

			hidePrompt();
			_promptContainer = new Sprite();
			_promptContainer.graphics.beginFill(0x121212, 0.95);
			_promptContainer.graphics.lineStyle(1, 0x2A2A2A);
			_promptContainer.graphics.drawRoundRect(0, 0, 300, 160, 8, 8);
			_promptContainer.graphics.endFill();
			_promptContainer.x = (960 - 300) / 2;
			_promptContainer.y = (500 - 160) / 2;
			
			var title:TextField = new TextField();
			title.defaultTextFormat = new TextFormat("_sans", 14, 0xE0E0E0, true, null, null, null, null, TextFormatAlign.CENTER);
			title.text = "Enter Shop ID:";
			title.width = 300;
			title.y = 10;
			title.selectable = false;
			_promptContainer.addChild(title);
			
			_promptInput = new TextField();
			_promptInput.type = TextFieldType.INPUT;
			_promptInput.defaultTextFormat = new TextFormat("_sans", 14, 0xFFFFFF);
			_promptInput.border = true;
			_promptInput.borderColor = 0x555555;
			_promptInput.background = true;
			_promptInput.backgroundColor = 0x222222;
			_promptInput.x = 20;
			_promptInput.y = 40;
			_promptInput.width = 260;
			_promptInput.height = 25;
			_promptInput.text = "";
			_promptContainer.addChild(_promptInput);
			
			var startBtn:Sprite = new Sprite();
			startBtn.graphics.beginFill(0x1E1E1E, 1);
			startBtn.graphics.lineStyle(1, 0x3A3A3A);
			startBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5);
			startBtn.graphics.endFill();
			startBtn.x = 20;
			startBtn.y = 80;
			startBtn.buttonMode = true;
			
			var startTxt:TextField = new TextField();
			startTxt.defaultTextFormat = new TextFormat("_sans", 12, 0xCCCCCC, true, null, null, null, null, TextFormatAlign.CENTER);
			startTxt.text = "Load";
			startTxt.width = 120;
			startTxt.y = 5;
			startTxt.selectable = false;
			startTxt.mouseEnabled = false;
			startBtn.addChild(startTxt);
			
			startBtn.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent):void { startBtn.graphics.clear(); startBtn.graphics.beginFill(0x333333, 1); startBtn.graphics.lineStyle(1, 0x555555); startBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); startBtn.graphics.endFill(); startTxt.textColor = 0xFFFFFF; });
			startBtn.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent):void { startBtn.graphics.clear(); startBtn.graphics.beginFill(0x1E1E1E, 1); startBtn.graphics.lineStyle(1, 0x3A3A3A); startBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); startBtn.graphics.endFill(); startTxt.textColor = 0xCCCCCC; });
			
			startBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				var sid:int = parseInt(String(_promptInput.text).replace(/^\s+|\s+$/g, ""));
				if (sid > 0) {
					AqwApi.shop.loadShop(sid);
					ApiNotificationManager.notify("Loading Shop: " + sid);
				}
				hidePrompt();
			});
			_promptContainer.addChild(startBtn);
			
			var cancelBtn:Sprite = new Sprite();
			cancelBtn.graphics.beginFill(0x1E1E1E, 1);
			cancelBtn.graphics.lineStyle(1, 0x3A3A3A);
			cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5);
			cancelBtn.graphics.endFill();
			cancelBtn.x = 160;
			cancelBtn.y = 80;
			cancelBtn.buttonMode = true;
			
			var cancelTxt:TextField = new TextField();
			cancelTxt.defaultTextFormat = new TextFormat("_sans", 12, 0xCCCCCC, true, null, null, null, null, TextFormatAlign.CENTER);
			cancelTxt.text = "Cancel";
			cancelTxt.width = 120;
			cancelTxt.y = 5;
			cancelTxt.selectable = false;
			cancelTxt.mouseEnabled = false;
			cancelBtn.addChild(cancelTxt);
			
			cancelBtn.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent):void { cancelBtn.graphics.clear(); cancelBtn.graphics.beginFill(0x333333, 1); cancelBtn.graphics.lineStyle(1, 0x555555); cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); cancelBtn.graphics.endFill(); cancelTxt.textColor = 0xFFFFFF; });
			cancelBtn.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent):void { cancelBtn.graphics.clear(); cancelBtn.graphics.beginFill(0x1E1E1E, 1); cancelBtn.graphics.lineStyle(1, 0x3A3A3A); cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); cancelBtn.graphics.endFill(); cancelTxt.textColor = 0xCCCCCC; });
			
			cancelBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				hidePrompt();
			});
			_promptContainer.addChild(cancelBtn);
			
			if (pocket.overlay != null) {
				pocket.overlay.addChild(_promptContainer);
			}
		}

		private static function showPastePrompt(pocket:*):void {
			hidePrompt();
			
			_promptContainer = new Sprite();
			_promptContainer.graphics.beginFill(0x121212, 0.95);
			_promptContainer.graphics.lineStyle(1, 0x2A2A2A);
			_promptContainer.graphics.drawRoundRect(0, 0, 600, 400, 8, 8);
			_promptContainer.graphics.endFill();
			
			_promptContainer.x = (960 - 600) / 2;
			_promptContainer.y = (500 - 400) / 2;
			
			var title:TextField = new TextField();
			title.defaultTextFormat = new TextFormat("_sans", 16, 0xE0E0E0, true, null, null, null, null, TextFormatAlign.CENTER);
			title.text = "Paste Script Below";
			title.width = 600;
			title.y = 10;
			title.selectable = false;
			title.mouseEnabled = false;
			_promptContainer.addChild(title);
			
			_promptInput = new TextField();
			_promptInput.type = TextFieldType.INPUT;
			_promptInput.multiline = true;
			_promptInput.wordWrap = true;
			_promptInput.defaultTextFormat = new TextFormat("_sans", 12, 0xFFFFFF);
			_promptInput.border = true;
			_promptInput.borderColor = 0x555555;
			_promptInput.background = true;
			_promptInput.backgroundColor = 0x222222;
			_promptInput.x = 20;
			_promptInput.y = 40;
			_promptInput.width = 560;
			_promptInput.height = 300;
			_promptContainer.addChild(_promptInput);
			
			var loadBtn:Sprite = new Sprite();
			loadBtn.graphics.beginFill(0x1E1E1E, 1);
			loadBtn.graphics.lineStyle(1, 0x3A3A3A);
			loadBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5);
			loadBtn.graphics.endFill();
			loadBtn.x = 160;
			loadBtn.y = 350;
			loadBtn.buttonMode = true;
			
			var loadTxt:TextField = new TextField();
			loadTxt.defaultTextFormat = new TextFormat("_sans", 12, 0xCCCCCC, true, null, null, null, null, TextFormatAlign.CENTER);
			loadTxt.text = "Load Script";
			loadTxt.width = 120;
			loadTxt.y = 5;
			loadTxt.selectable = false;
			loadTxt.mouseEnabled = false;
			loadBtn.addChild(loadTxt);
			
			loadBtn.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent):void { loadBtn.graphics.clear(); loadBtn.graphics.beginFill(0x333333, 1); loadBtn.graphics.lineStyle(1, 0x555555); loadBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); loadBtn.graphics.endFill(); loadTxt.textColor = 0xFFFFFF; });
			loadBtn.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent):void { loadBtn.graphics.clear(); loadBtn.graphics.beginFill(0x1E1E1E, 1); loadBtn.graphics.lineStyle(1, 0x3A3A3A); loadBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); loadBtn.graphics.endFill(); loadTxt.textColor = 0xCCCCCC; });
			
			loadBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				var text:String = _promptInput.text;
				hidePrompt();
				ScriptManager.SINGLETON.loadScript(text);
				ApiNotificationManager.notify("Script loaded successfully!");
			});
			_promptContainer.addChild(loadBtn);
			
			var cancelBtn:Sprite = new Sprite();
			cancelBtn.graphics.beginFill(0x1E1E1E, 1);
			cancelBtn.graphics.lineStyle(1, 0x3A3A3A);
			cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5);
			cancelBtn.graphics.endFill();
			cancelBtn.x = 320;
			cancelBtn.y = 350;
			cancelBtn.buttonMode = true;
			
			var cancelTxt:TextField = new TextField();
			cancelTxt.defaultTextFormat = new TextFormat("_sans", 12, 0xCCCCCC, true, null, null, null, null, TextFormatAlign.CENTER);
			cancelTxt.text = "Cancel";
			cancelTxt.width = 120;
			cancelTxt.y = 5;
			cancelTxt.selectable = false;
			cancelTxt.mouseEnabled = false;
			cancelBtn.addChild(cancelTxt);
			
			cancelBtn.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent):void { cancelBtn.graphics.clear(); cancelBtn.graphics.beginFill(0x333333, 1); cancelBtn.graphics.lineStyle(1, 0x555555); cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); cancelBtn.graphics.endFill(); cancelTxt.textColor = 0xFFFFFF; });
			cancelBtn.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent):void { cancelBtn.graphics.clear(); cancelBtn.graphics.beginFill(0x1E1E1E, 1); cancelBtn.graphics.lineStyle(1, 0x3A3A3A); cancelBtn.graphics.drawRoundRect(0, 0, 120, 30, 5, 5); cancelBtn.graphics.endFill(); cancelTxt.textColor = 0xCCCCCC; });
			
			cancelBtn.addEventListener(MouseEvent.CLICK, function(e:MouseEvent):void {
				hidePrompt();
			});
			_promptContainer.addChild(cancelBtn);
			
			if (pocket.overlay != null) {
				pocket.overlay.addChild(_promptContainer);
			}
		}

		private static function hidePrompt():void {
			if (_promptContainer != null && _promptContainer.parent != null) {
				_promptContainer.parent.removeChild(_promptContainer);
			}
			_promptContainer = null;
			_promptInput = null;
		}

		public static function stickyNotification(overlay:Overlay, id:String, message:String):void {
			ApiNotificationManager.instance.createSticky(id, message);
		}

		public static function removeStickyNotification(overlay:Overlay, id:String):void {
			ApiNotificationManager.instance.removeSticky(id);
		}
	}
}
