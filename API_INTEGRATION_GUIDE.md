# AqwApi & ModUI Integration Guide (Single-Hook Bootstrap)

This document explains how our custom Haxe automation engine (`AqwApi`) and Mod UI (`ModUI`) are integrated into Anthony's upstream `aqw-mobile` client using a decoupled 3-repository architecture.

---

## 1. The 3-Repository Ecosystem

To ensure upstream purity, maintainability, and clean separation of concerns, the project is structured into three independent repositories:

| Repository | Tech Stack | Role & Responsibility | Output |
| :--- | :--- | :--- | :--- |
| [**`aqw-haxe-api`**](https://github.com/JonasAlv/aqw-haxe-api) | Haxe / hscript | **Headless Automation API**: Game packets, map state, combat manager, quest runner, inventory/drops, entity tracking, and script interpreter. Zero UI dependencies. | `bin/AqwApi.swc` |
| [**`aqw-haxe-ui`**](https://github.com/JonasAlv/aqw-haxe-ui) | Haxe / Flash | **Mod UI & Menus Library**: Floating draggable Menu button, mod tabs (Scripts, Automation, Enhancements, Settings), HUD toast notifications, and modal dialogs. | `bin/ModUI.swc` |
| [**`aqw-mobile-mod`**](https://github.com/JonasAlv/aqw-mobile-mod) | ActionScript 3 (AIR) | **Upstream Host Client**: Upstream client tracking [Anthony's `aqw-mobile`](https://github.com/anthony-hyo/aqw-mobile). Consumes compiled SWCs in `loader/libs/`. | Injected `Desktop.swf` / `.apk` |

---

## 2. The ONLY Hook Required: `Pocket.as` (1-Line Connection)

Our goal is **zero touchpoints inside Anthony's upstream game files**. We do NOT modify `Overlay.as`, `GameLoad.as`, `World.as`, or any UI option controls.

The entire mod requires **only 1 single line** in `loader/src/Pocket.as`:

**Location:** Inside the `Pocket` constructor (after `_SINGLETON = this;`):
```actionscript
    check();

    _SINGLETON = this;

    // [MOD] 1-Line Hook: Bootstraps AqwApi, ModUI, and Desktop subsystems
    ModBootstrap.init(this);
```

---

## 3. How `ModBootstrap.as` Bridges Everything

`loader/src/ModBootstrap.as` acts as the single bridge between Anthony's client and our compiled Haxe libraries:

1. **Loads Precompiled SWCs**:
   `amxmlc` automatically includes all libraries in `loader/libs/` via `-library-path+=loader/libs`:
   - `loader/libs/AqwApi.swc` (from `aqw-haxe-api`)
   - `loader/libs/ModUI.swc` (from `aqw-haxe-ui`)
2. **Injects Mod Menus**:
   Calls `ui.ApiMenus.inject(pocket.overlay)` which attaches the draggable red "Menu" button and hooks panel navigation via ActionScript event listeners.
3. **Initializes Game Automation**:
   Attaches an `ENTER_FRAME` listener to detect when `pocket.game` finishes loading, then invokes `com.aqwapi.AqwApi.init(pocket.game)`.
4. **Enables Desktop Features**:
   Initializes gamepad support (`DesktopInputManager`) on desktop builds and applies SWF RAM cache settings.

---

## 4. Upgrading to a New Upstream Version

When Anthony releases a new version of `aqw-mobile`:
1. Pull or copy his updated `loader/src/` files into this repository.
2. Add the single 1-line hook in `loader/src/Pocket.as`:
   ```actionscript
   ModBootstrap.init(this);
   ```
3. Run `./build.sh` (or `haxe-workspace/build.sh`) to compile and inject into `Desktop.swf`!
