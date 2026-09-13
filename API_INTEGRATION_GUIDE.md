# AqwApi Integration Guide

This document explains exactly how our custom API (`AqwApi`) is hooked into Anthony's upstream `aqw-mobile` base game files. If you ever update Anthony's base files again, these are the ONLY hooks you need to ensure remain intact.

## 1. The Goal
Our goal is to **not hack his core logic** (`Pocket.as`, `Game.as`, `Core.as`, etc.). We keep his base game completely clean and only hook into his UI overlay to inject our standalone API.

## 2. Core Hook: `ui/Overlay.as`
This is the single entry point where we intercept his UI to load our custom bot menus and notification manager.

**Location:** Inside `ui.Overlay` -> `initFrame()`
**What to add:**
```actionscript
private function initFrame():void {
    // 1. Inject our custom BotMenus so they appear in the UI
    BotMenus.inject(this);
    
    // 2. Initialize our independent ApiNotificationManager
    apiNotifications = Sprite(addChild(new Sprite()));
    ApiNotificationManager.instance.init(apiNotifications);

    // ... (rest of Anthony's original code)
}
```

## 3. Configuration Overrides (Optional): `ui/Overlay.as`
Anthony uses `Pocket.SINGLETON.config.*` to save his settings. We override some of these in `Overlay.as` to use our custom `Config` class instead, completely detaching his config system from ours.

**Example Change in his Checkboxes:**
```actionscript
function (option:Check):void {
    // OLD: Pocket.SINGLETON.config.option_animation_monster_off = option.state;
    // NEW: Config.IS_GRAPHIC_ANIMATION_MONSTER_OFF = option.state;
}
```

## 4. Standalone UI Components (No Upstream Modifications Required)
We added the following files natively to `loader/src/ui/`. These files completely replace his `Notification.as` dependency:
*   `BotMenus.as`: Contains the UI for the bot options and completely relies on `AqwApi.dispatcher`.
*   `ApiNotificationManager.as`: Intercepts `ApiEvent.NOTIFICATION` events globally.
*   `ApiNotification.as`: Renders the sleek dark Material UI notification on the screen.

Because these are standalone, an update from Anthony will **never** overwrite them.

## 5. Summary
By keeping `Pocket.as` 100% untouched and injecting our code exclusively via `Overlay.as.initFrame()`, we achieved a fully modular architecture. 

**Updating to a new version is as simple as:**
1. Downloading his new `src` folder.
2. Dropping our `BotMenus.as`, `ApiNotification.as`, and `ApiNotificationManager.as` files inside.
3. Adding the two hook lines back into `Overlay.as.initFrame()`.
