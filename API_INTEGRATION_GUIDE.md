# AqwApi Integration Guide (Single-Hook Bootstrap)

This document explains exactly how our custom API (`AqwApi`) and Bot UI are hooked into Anthony's upstream `aqw-mobile` base game files.

## 1. The Goal
Our goal is **zero-touch / minimal touchpoints to upstream files**. We do NOT modify `Overlay.as`, `GameLoad.as`, or any core UI/network files. 

All initialization is encapsulated into `ModBootstrap.as`.

---

## 2. The ONLY Hook Required: `Pocket.as`

The entire mod requires **only 1 single line** in `loader/src/Pocket.as`:

**Location:** Inside `Pocket` constructor (at the bottom, right after `_SINGLETON = this;`):
```actionscript
    check();

    _SINGLETON = this;

    // [MOD] Bootstrap all API, UI, and desktop subsystems
    ModBootstrap.init(this);
```

---

## 3. What `ModBootstrap` Handles Automatically

Because of `ModBootstrap.as`, you **do not** need to touch:
*   `load/handlers/GameLoad.as`: `ModBootstrap` watches `pocket.game` and invokes `AqwApi.init(pocket.game)` automatically when the game object is loaded.
*   `ui/Overlay.as`: `ModBootstrap` injects `ApiMenus` and `ApiNotificationManager` from the outside using event listeners.
*   `ui/option/Menu.as`: Menu tab selection and state retention (`lastSelectedMenu`) are handled purely via event delegation in `ApiMenus.as`.
*   Gamepad controls: `DesktopInputManager` is wired automatically for Desktop builds.
*   RAM SWF cache: `pocket.config.option_swf_cache` is initialized automatically.

---

## 4. Standalone Mod Components (No Upstream Modifications Required)
Our mod files live independently in `loader/src/`:
*   `ModBootstrap.as`: Central coordinator and lifecycle hook.
*   `ui/ApiMenus.as`: Custom dark UI overlay with bot options, scripts, quests, combat loadouts, and drop filters.
*   `ui/ApiNotification.as` & `ui/ApiNotificationManager.as`: HUD notifications for bot actions and events.
*   `ui/option/Dropdown.as`: Dropdown UI control for class and skill mode selection.
*   `controller/gamepad/DesktopInputManager.as`: Controller support for Desktop.

---

## 5. Upgrading to a New Upstream Version

When Anthony releases a new version of `aqw-mobile`:
1. Drop his new `loader/src/` files into your workspace.
2. Add the single line in `loader/src/Pocket.as`:
   ```actionscript
   ModBootstrap.init(this);
   ```
3. Run `./build.sh`!
