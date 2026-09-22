# AQW Mobile Mod

A modded version of [Anthony's `aqw-mobile`](https://github.com/anthony-hyo/aqw-mobile) client, integrated with a high-performance Haxe automation engine and custom in-game mod menus.

---

## Architecture: 3-Repository Ecosystem

To ensure upstream purity, effortless upgrades, and decoupled components, the project is structured across three repositories:

* [**`aqw-haxe-api`**](https://github.com/JonasAlv/aqw-haxe-api): **Headless Automation Engine** in Haxe. Handles packet intercepts, monster/player tracking, smart combat rotations, auto-questing, inventory/drop management, and the `hscript` runtime. Compiles to `AqwApi.swc`.
* [**`aqw-haxe-ui`**](https://github.com/JonasAlv/aqw-haxe-ui): **Mod UI & Menus Library** in Haxe. Provides the draggable floating "Menu" button, mod tabs (Scripts, Automation, Enhancements, Settings), HUD toasts, and prompt modals. Compiles to `ModUI.swc`.
* [**`aqw-mobile-mod`**](https://github.com/JonasAlv/aqw-mobile-mod): **Host Client Loader** (this repository). Maintains upstream cleanliness from Anthony's repository, linking `AqwApi.swc` and `ModUI.swc` via a single 1-line hook in `Pocket.as`:
  ```actionscript
  ModBootstrap.init(this);
  ```

---

## Mod Features

* **Automation & Scripting**:
  * Built-in HScript engine supporting script loading via file browser or raw text paste.
  * In-game chat logger displaying script and bot logs directly inside the AQW chat box.
  * Class Loadouts configuration for automatic Farm, Solo, Boss, and Dodge class swapping.
* **AutoCombat**:
  * Smart Combat: Automatically adapts skill rotations based on equipped class and mode.
  * Custom Combat: Configure custom skill chains with target detection and loop timings.
* **Quality of Life**:
  * **Infinite Range**: Attack and cast skills across the entire screen without range limits.
  * **Death Spawn (Same Room)**: Automatically sets your respawn location to your current room.
  * **Private Rooms**: Automatically joins private room instances (e.g., `/join battleon-100000`).
  * **Drop Filters**: Auto-accept all drops or filter specifically for AC-tagged (coin) items.
  * **Shop & Bank**: Load shops by ID on the fly and toggle your bank anywhere.
  * **Enhancements**: Quick-load normal level 50+, Awe, and Forge enhancement shops.

---

## Building Locally

### Prerequisites
* Adobe AIR SDK 51+ (`AIRSDK_Linux` or `AIRSDK_Windows`)
* Java 21+ (`JAVA_HOME`)
* Haxe 4.3+ (`haxe` and `haxelib install hscript`)
* RABCDAsm (`abcexport`, `abcreplace`)

### Desktop Build
```bash
./build.sh
```
This automatically compiles `aqw-haxe-api` $\rightarrow$ `aqw-haxe-ui` $\rightarrow$ injects into `loader/Desktop.swf`.

### Launching (via Wine/ADL)
```bash
./run.sh
```

### Android APK Build
```bash
./build-android.sh
```

For detailed architecture and hook explanation, see [API_INTEGRATION_GUIDE.md](API_INTEGRATION_GUIDE.md).