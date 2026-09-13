# AqwApi Integration Guide

This document explains exactly how our custom API (`AqwApi`) is hooked into Anthony's upstream `aqw-mobile` base game files. If you ever update Anthony's base files again, these are the ONLY hooks you need to ensure remain intact.

## 1. The Goal
Our goal is to **minimize changes to his core logic**. We keep his base game as clean as possible, enforcing direct, explicit, and deterministic hooks so developers aren't running in circles tracking down background magic.

## 2. API Initialization Hook: `load/handlers/GameLoad.as`
This is where we explicitly initialize `AqwApi` the exact millisecond the game object is successfully loaded and appended to the stage.

**Location:** Inside `load.handlers.GameLoad` -> `onCompleted()`
**What to add:**
```actionscript
    import com.aqwapi.AqwApi;
    // ...
    this.pocket.gameCore.onFrameChange("Init");

    // [MOD] Initialize our custom API with the fresh game object!
    AqwApi.init(this.pocket.game);

    this.pocket.advance();
```

## 3. UI Hook: `ui/Overlay.as`
This is where we intercept his UI to load our custom bot menus and notification manager.

**Location:** Inside `ui.Overlay` -> `initFrame()`
**What to add:**
```actionscript
private function initFrame():void {
    // [MOD] Inject our custom BotMenus so they appear in the UI
    BotMenus.inject(this);
    
    // [MOD] Initialize our independent ApiNotificationManager
    apiNotifications = Sprite(addChild(new Sprite()));
    ApiNotificationManager.instance.init(apiNotifications);

    // ... (rest of Anthony's original code)
}
```

## 4. Configuration Overrides (Optional): `ui/Overlay.as`
Anthony uses `Pocket.SINGLETON.config.*` to save his settings. We override some of these in `Overlay.as` to use our custom `Config` class instead, completely detaching his config system from ours.

**Example Change in his Checkboxes:**
```actionscript
function (option:Check):void {
    // OLD: Pocket.SINGLETON.config.option_animation_monster_off = option.state;
    // NEW: Config.IS_GRAPHIC_ANIMATION_MONSTER_OFF = option.state;
}
```

## 5. Standalone UI Components (No Upstream Modifications Required)
We added the following files natively to `loader/src/ui/`. These files completely replace his `Notification.as` dependency:
*   `BotMenus.as`: Contains the UI for the bot options and completely relies on `AqwApi.dispatcher`.
*   `ApiNotificationManager.as`: Intercepts `ApiEvent.NOTIFICATION` events globally.
*   `ApiNotification.as`: Renders the sleek dark Material UI notification on the screen.

Because these are standalone, an update from Anthony will **never** overwrite them.

## 6. Summary
By keeping hooks strictly to `GameLoad.as` (initialization) and `Overlay.as` (UI injection), we maintain a fully deterministic and modular architecture. 

**Updating to a new version is as simple as:**
1. Downloading his new `src` folder.
2. Dropping our `BotMenus.as`, `ApiNotification.as`, and `ApiNotificationManager.as` files inside.
3. Adding the initialization hook into `GameLoad.as`.
4. Adding the UI hook into `Overlay.as`.
