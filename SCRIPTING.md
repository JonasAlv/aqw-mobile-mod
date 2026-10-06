# AQW Haxe Scripting API Guide (.hxs)

Welcome to the official scripting guide for the AQW Client Mod. Scripts are written in **HScript** (`.hxs` files) — a lightweight, dynamic scripting language with standard JavaScript/ActionScript 3 syntax executing live inside the client engine.

---

## Table of Contents
1. [Core Philosophy & Execution Model](#1-core-philosophy--execution-model)
2. [Script Lifecycle Hooks](#2-script-lifecycle-hooks)
3. [The 3 Official Scripting Patterns](#3-the-3-official-scripting-patterns)
   - [Pattern 1: The Deterministic Step-by-Step Saga (Error-Proof Standard)](#pattern-1-the-deterministic-step-by-step-saga)
   - [Pattern 2: The Goal / Hardfarm Loop](#pattern-2-the-goal--hardfarm-loop)
   - [Pattern 3: Ambient Single-Zone Auto-Farm](#pattern-3-ambient-single-zone-auto-farm)
4. [Top-Level DSL Reference](#4-top-level-dsl-reference)
   - [Navigation & Map Movement](#navigation--map-movement)
   - [Combat & Hunting](#combat--hunting)
   - [Quest Automation & Progression](#quest-automation--progression)
   - [Inventory, Bank & Shopping](#inventory-bank--shopping)
   - [Drops & Loot](#drops--loot)
   - [Server Boosts](#server-boosts)
   - [Auras & Client Memory Maintenance](#auras--client-memory-maintenance)
   - [Character Status & Factions](#character-status--factions)
   - [Execution Control, Logging & System](#execution-control-logging--system)
5. [Hardfarm Item Presets (21 Built-in Presets)](#5-hardfarm-item-presets)
6. [Subsystem Namespaces Reference](#6-subsystem-namespaces-reference)
7. [Essential Rules & Best Practices](#7-essential-rules--best-practices)
8. [AI Script Generation Prompting Guide](#8-ai-script-generation-prompting-guide)

---

## 1. Core Philosophy & Execution Model

The Flash/ActionScript 3 runtime is **single-threaded**. There is no background thread for blocking execution; scripts run tick-by-tick inside the game's timeline loop (typically every 100–250ms).

Because of this, the most reliable and error-proof way to script is the **Idempotent State Evaluator**:
- **Every tick checks live game state:** Scripts do not maintain fragile local stage counters (`var step = 3;`). Instead, each tick inspects actual quest completion, inventory counts, and map status directly from the game server.
- **Self-Healing on Disconnect or Death:** If you disconnect, respawn, change rooms, or lag, the next tick automatically re-evaluates what is needed and picks up right where you left off.
- **Fast Skipping:** A completed quest check (`quest(id)`) evaluates to `false` in 0ms and skips immediately to the next task.

### The Default Identifier Rule (Strict Standard)
- **Quests $\rightarrow$ Strictly Numeric Quest IDs:**
  ```javascript
  if (quest(2239, "thespan")) { ... }
  if (ensureQuest(7551)) { ... }
  autoQuest([9421, 9422, 9423]);
  ```
  The AQW server protocol (`%xt%zm%getQuest%1%<id>%`) only queries quests by numeric ID. Never use quest names.
- **Map Items $\rightarrow$ Strictly Numeric MapItem IDs:**
  ```javascript
  if (!mapItem(1358, "Tek's Notes", 1)) return;
  ```
  Ground collectibles are embedded as numeric IDs in map SWFs.
- **Monsters & Items $\rightarrow$ Clean, Human-Readable Names:**
  ```javascript
  if (!hunt("Shadow Siphon", "Shadow Residue", 6)) return;
  if (!hasItem("Elders' Blood", 1)) return;
  ```
  Monster and item names live permanently in live memory and match in-game quest text directly (numeric IDs remain supported for disambiguating duplicate items/spawns).

---

## 2. Script Lifecycle Hooks

Every `.hxs` script defines three entry points:

```javascript
function onStart() {
    // Runs once when the script is started.
    // Use for setup: drop policies, gear loadouts, and unbanking presets.
    log("Starting script...");
    acceptAllDrops();
    equipLoadout("farm");
    unbankPreset("vhl");
}

function onTick() {
    // Runs repeatedly every tick (100–250ms).
    // Implement your main logic loop or step-by-step quest cascade here.
}

function onStop() {
    // Runs once when the script finishes or the user clicks Stop.
    // Use for safe cleanup: stopping combat and parking safely in house.
    log("Script finished.");
    stopCombat();
    ensureHouse();
}
```

---

## 3. The 3 Official Scripting Patterns

### Pattern 1: The Deterministic Step-by-Step Saga
Use this pattern for storyline progression, saga chapters, and one-time quest chains.

```javascript
// Example: The Span Saga Chapter
var checkedProgress = false;

function onStart() {
    checkedProgress = false;
    log("Starting The Span saga...");
    acceptAllDrops();
    setSkipCutscenes(true);
    equipLoadout("farm");
}

function onTick() {
    // Safe startup: pre-load quests from your private house
    if (!checkedProgress) {
        if (!isHouse()) { ensureHouse(); return; }
        if (!ensureQuestsLoaded([2239, 2240, 2241, 2519])) return;
        checkedProgress = true;
        log("Quests verified. Proceeding...");
    }

    // Step 1: River Frogzards & Water
    if (quest(2239, "thespan")) {
        if (!hunt("Shadow Siphon", "Shadow Residue", 6)) return;
        if (!mapItem(1358, "Tek's Notes", 1)) return;
        complete(2239);
        return;
    }

    // Step 2: Time Library Keys
    if (quest(2240, "timelibrary")) {
        if (!hunt("Sneak", "AQ Dimension Key", 1)) return;
        if (!hunt("Tog", "DF Dimension Key", 1)) return;
        complete(2240);
        return;
    }

    // Step 3: Boss fight with solo loadout switch
    if (quest(2519, "timespace")) {
        equipLoadout("solo");
        if (!hunt("Chaos Lord Iadoa", "Iadoa Defeated", 1)) return;
        complete(2519);
        return;
    }

    // All quests complete
    log("Saga chapter finished!");
    ensureHouse();
    stop();
}

function onStop() {
    ensureHouse();
}
```

#### Why Step-by-Step Never Breaks:
1. `quest(id, map)` returns `false` in 0ms if the quest is already done, immediately falling through to the next step.
2. `hunt(...)` returns `false` while actively collecting and `true` when all requirements are in your backpack.
3. Returning early (`if (!hunt(...)) return;`) yields control back to the engine until the next tick.
4. `complete(id)` automatically drops combat, turns in the quest, and verifies server completion. Once acknowledged, the step is skipped on the subsequent tick.

---

### Pattern 2: The Goal / Hardfarm Loop
Use this pattern for end-game repeatable turn-ins (e.g. Void Highlord, Legion Revenant, ArchMage).

```javascript
function onStart() {
    log("Starting VHL farm...");
    acceptAllDrops();
    equipLoadout("farm");
    // Unbank all reagents so incoming drops do not route directly to the bank
    unbankPreset("vhl");
}

function onTick() {
    // 1. Goal Check: Terminate once target count is reached
    if (hasItem("Roentgenium of Nulgath", 15)) {
        log("Goal reached: 15 Roentgeniums!");
        ensureHouse();
        stop();
        return;
    }

    // 2. Repeatable Quest: Void Highlord Challenge
    if (ensureQuest(7551)) {
        if (!hasItem("Elders' Blood", 1)) {
            log("Missing daily Elders' Blood! Halting.");
            stop();
            return;
        }
        if (!hunt("Dark Makai", "Dark Makai Defeated", 50)) return;
        if (!huntItem("Mana Golem", "Mana Energy for Nulgath", 1, "elemental")) return;
        complete(7551);
        return;
    }
}

function onStop() {
    stopCombat();
    ensureHouse();
}
```

---

### Pattern 3: Ambient Single-Zone Auto-Farm
Use this pattern for repetitive leveling, class points, or zone-specific token farming.

```javascript
function onStart() {
    log("Starting ShadowBattleon leveling...");
    acceptAllDrops();
    equipLoadout("farm");
    join("shadowbattleon", "Enter", "Spawn");
    // autoQuest handles acceptance, requirement checks, and turn-ins automatically
    autoQuest([9421, 9422, 9423]);
}

function onTick() {
    ensureMap("shadowbattleon", "Enter", "Spawn");
    ensureCombat();
}

function onStop() {
    log("Stopping leveling farm...");
    stopAutoQuest();
    stopCombat();
    ensureHouse();
}
```

---

## 4. Top-Level DSL Reference

All functions listed below are globally available in `.hxs` scripts without any namespace prefix.

> [!IMPORTANT]
> **The Default Identifier Rule (Strict Standard)**:
> - **Quests $\rightarrow$ Strictly Numeric Quest IDs (`quest(2239)`)**: The AQW server protocol (`%xt%zm%getQuest%1%<id>%`) strictly requires numeric IDs to request quests from the server. Using numeric IDs guarantees the script can load and verify quests from anywhere (including your house on startup).
> - **Map Items $\rightarrow$ Strictly Numeric MapItem IDs (`mapItem(1358, 1)`)**: Map collectibles are numeric IDs hardcoded in map SWFs.
> - **Monsters, Items & Drops $\rightarrow$ Clean Human-Readable Names (`hunt("Dark Makai", "Dark Makai Defeated", 50)`)**: Monster and item names are permanently present in map and inventory memory and match in-game quest logs directly. Numeric IDs remain supported for disambiguation.

### Navigation & Map Movement
- `ensureMap(mapName, cell?, pad?)` *(Bool)*: Ensures you are in `mapName` and cell. Drops combat stealthily before transferring. Automatically routes `"house"` to your personal house.
- `ensureHouse()` *(Bool)*: Drops combat and teleports to your private house. Returns `true` once loaded.
- `join(mapName, cell?, pad?)`: Initiates map transfer.
- `joinHouse(username?)`: Joins your house or the house of `username`.
- `isHouse()` *(Bool)*: Returns `true` if currently in your house.
- `isMap(name)` *(Bool)*: Returns `true` if currently on `name`.
- `isCell(name)` *(Bool)*: Returns `true` if avatar is in `name`.
- `isLoaded()` *(Bool)*: Returns `true` if current map is fully loaded.
- `jump(cell, pad?, autoCorrect? = true)`: Jumps to specified cell/pad. Automatically verifies timeline pads and auto-corrects missing pads.
- `jumpCorrect(cell, pad?)`: Forces immediate jump with live pad auto-correction.
- `ensureCell(cell, pad?)` *(Bool)*: Ensures avatar is in `cell`, jumping if necessary.
- `mapName()` / `getMapName()` *(String)*: Current map name.
- `cell()` / `getCell()` *(String)*: Current cell name.
- `pad()` / `getPad()` *(String)*: Current pad name.
- `getMapCells()` *(Array<String>)*: Returns all frame labels on the map timeline.
- `getCellPads()` *(Array<String>)*: Returns valid pad names for current cell.
- `walkThroughWalls(enabled? = true)` / `disableCollisions(enabled? = true)`: Clears obstacle collision bounds (`arrSolid` / `arrSolidR`), allowing unrestricted pathing across any map obstacle. Maintained across cell jumps.
- `skipCutscenes()` / `skipCutscene()`: Instantly clears external cutscene SWFs (`mcExtSWF`), removes modal blocking overlays, and restores game UI.
- `setSkipCutscenes(enabled? = true)` / `autoSkipCutscenes(enabled? = true)`: Automatically skips cutscenes when entering rooms.
- `isSkipCutscenes()` *(Bool)*: Returns `true` if auto-skipping cutscenes is enabled.

---

### Combat & Hunting
- `hunt(monster, item, qty = 1, callback?)` *(Bool)*: Hunts `monster` (name or ID) until backpack or temp inventory holds `qty` of `item` (name or ID). Returns `true` when satisfied.
- `hunt(monster, count, callback?)` *(Bool)*: Hunts `monster` (name or ID) until `count` total kills are reached. Returns `true` when satisfied.
- `hunt(["Minion", "Boss"], item, qty = 1)` *(Bool)*: **Priority Targeting**: Hunts in specified priority order. Kills the minion first; switches to boss when minion is dead; immediately switches back to minion if it respawns (e.g. `hunt(["Staff of Inversion", "Escherion"], "Relic of Chaos", 1)`).
- `hunt(monster, item, qty, { priority: [...], huntPriority: "...", counterHandler: true, aggro: true, pull: true })` *(Bool)*: Hunts with combat options:
  - `priority`: Array of minion/add targets to kill before primary boss.
  - `huntPriority`: Targeting strategy (`"lowest_hp"`, `"highest_hp"`, or `"closest"`).
  - `counterHandler`: `true` to auto-pause DPS during reflect/counter auras.
  - `pauseOnAuras`: Custom aura names to pause on.
  - `aggro` / `aggroAll`: `true` to auto-aggro all monsters in the cell via server packets.
  - `pull` / `pullAll`: `true` to continuously stack all monsters directly on player coordinates for maximum AoE cleave.
- `hunt(monster, itemsArray, callback?)` *(Bool)*: Hunts `monster` for multiple items (e.g. `["Item A:10", "Item B:5"]`).
- `hunt(monster, item, qty, mmid, callback?)` *(Bool)*: Strictly locks onto a specific Map Monster ID (MMID) spawn.
- `hunt("*", count)` / `hunt("*", item, qty)`: Wildcard target; attacks any monster in the cell until count/items are met.
- `kill(...)` *(Bool)*: Direct alias for `hunt(...)`.
- `huntItem(monster, item, qty = 1, map?)` *(Bool)*: Navigates to `map`, checks inventory, and hunts for `item` (name or ID).
- `huntMonster(monster, kills = 1, map?)` *(Bool)*: Navigates to `map` and hunts by kill count.
- `attack(monster)`: Targets and attacks monster (name or ID).
- `setTargetPriority(["Minion", "Boss"])`: Sets priority target order for combat engine.
- `setHuntPriority("lowest_hp" | "highest_hp" | "closest")`: Sets target selection strategy when multiple candidates are alive.
- `aggro(monster?)`: Aggros a specific monster or any living monster in the current cell.
- `aggroMonsters(targets?)`: Sends server `%xt%zm%aggroMon%` packet to engage all (or specified) living monsters in the current cell.
- `aggroAll(enabled? = true)`: Enables continuous server-side aggro pulling for all monsters in the cell during combat.
- `pullMonsters(targets?)`: Aggros and stacks all (or specified) living monsters in the cell directly onto player coordinates.
- `pull(targets?)`: Direct alias for `pullMonsters(targets?)`.
- `pullAll(enabled? = true)`: Continuously pulls and stacks all living monsters in the cell onto player coordinates throughout combat.
- `magnetize()`: Stacks the currently targeted monster directly onto player coordinates.
- `magnetizeAll(targets?)`: Stacks all (or specified) living monsters in the cell directly onto player coordinates.
- `counterHandler(enabled? = true)` / `enableCounterHandler(enabled? = true)`: Enables the **Auto Counter & Reflect Aura Handler**. Automatically halts auto-attacks and skill casts when target has a reflect or counter aura (`"Counter Attack"`, `"Fox"`, `"Retaliate"`, `"Reflect"`, `"Damage Reflect"`, `"Reflective Shield"`, `"Talon Twisting"`). Keeps target locked and resumes the exact millisecond the aura expires.
- `pauseOnAuras(auras)`: Registers custom aura names to pause on (e.g. `["Counter Attack", "Fox"]` or `"Fox, Reflect"`).
- `clearPauseAuras()`: Clears custom pause auras.
- `isPausedByAura()` *(Bool)*: Returns `true` if combat is actively paused waiting for a reflect/counter aura to expire.
- `getBestTarget(nameOrId? = "*")` *(Object)*: Finds the optimal living monster in current cell.
- `getBestMonsterTarget(cell?, nameOrId? = "*")` *(Object)*: Finds optimal living monster in cell.
- `sortByLowestHp(monsters)` *(Array)*: Sorts an array of monster objects by lowest current HP ascending.
- `sortByHighestHp(monsters)` *(Array)*: Sorts an array of monster objects by highest current HP descending.
- `sortByClosest(monsters)` *(Array)*: Sorts an array of monster objects by distance to player avatar.
- `stopCombat()`: Drops target, halts auto-attack, and stealthily drops aggro in-place.
- `ensureCombat(smart? = true)`: Ensures combat engine is active.
- `equipLoadout("farm" | "solo" | "support")` *(Bool)*: Equips configured class, equipment, and combat rotation mode.
- `resetHunt()`: Clears active hunt target, priority targets, counters, and hunt aggro/pull states.

---

### Quest Automation & Progression
- `quest(questId, mapName?)` *(Bool)*: Skips block if quest is already completed; otherwise ensures map, accepts quest, and returns `true`.
- `complete(questId, choice?)` *(Bool)*: Drops combat, turns in quest (with optional choice reward ID/name), and verifies server completion.
- `ensureQuest(questId)` / `ensureAccept(questId)` *(Bool)*: Ensures quest is loaded and accepted. Returns `true` if already completed.
- `canComplete(questId)` / `isQuestComplete(questId)` *(Bool)*: Returns `true` if all turn-in requirements are met.
- `hasBeenCompleted(questId)` / `isCompletedBefore(questId)` *(Bool)*: Returns `true` if quest was completed previously.
- `isQuestUnlocked(questId)` / `isUnlocked(questId)` *(Bool)*: Returns `true` if quest is unlocked.
- `isQuestAccepted(questId)` *(Bool)*: Returns `true` if quest is currently in progress.
- `ensureQuestsLoaded(questIds)` *(Bool)*: Pre-loads an array or single ID of quest definitions from server.
- `areQuestsLoaded(questIds)` *(Bool)*: Returns `true` once all specified quest definitions are loaded.
- `loadQuest(questId)` / `loadQuests(questIds)`: Requests quest definitions from server by ID.
- `acceptQuest(questId)`: Sends raw accept packet for loaded quest.
- `completeQuest(questId, choice?)`: Sends raw turn-in packet without waiting.
- `getMissingRequirements(questId)` *(Array)*: Returns array of outstanding requirement objects.
- `mapItem(itemId, item, qty = 1, map?)` *(Bool)*: Gathers map item until inventory holds `qty` of `item` (name or ID).
- `mapItem(itemId, qty = 1)` *(Bool)*: Collects map item `qty` times (for quest requirements with no inventory item).
- `getMapItem(itemId)` *(Bool)*: Single-click map item pickup (rate-limited to 1500ms).
- `resetMapItems()`: Clears gathered map-item count history.
- `autoQuest([questIds])`: Starts automated background questing (accepts, monitors requirements, turns in).
- `stopAutoQuest()`: Stops background auto-questing.
- `isAutoQuestRunning()` *(Bool)*: Returns `true` if auto-questing is active.

---

### Inventory, Bank & Shopping
- `hasItem(nameOrId, qty = 1)` *(Bool)*: Checks if backpack or temp inventory holds `qty` of item (by name or ItemID).
- `getItemCount(nameOrId)` *(Int)*: Returns quantity in backpack.
- `getQuestQuantity(nameOrId)` *(Int)*: De-duplicated count across backpack, temp inventory, and quest trees.
- `getInventoryQuantity(nameOrId)` *(Int)*: Quantity in backpack only.
- `getBankQuantity(nameOrId)` *(Int)*: Quantity in bank storage.
- `getTempQuantity(nameOrId)` *(Int)*: Quantity in temporary quest container.
- `hasTempItem(nameOrId, qty = 1)` *(Bool)*: Returns `true` if temp container holds `qty`.
- `getItemLocation(nameOrId)` *(String)*: Returns `"temp"`, `"inventory"`, `"bank"`, `"house"`, or `""`.
- `findItem(nameOrId)` *(Object)*: Returns `{ item, id, name, quantity, location }` or `null`.
- `getInventory()` *(Array)*: Returns all backpack item objects.
- `getBankItems()` *(Array)*: Returns all banked item objects.
- `getTempItems()` *(Array)*: Returns all temporary quest item objects.
- `equip(nameOrId)`: Equips item by name or ItemID.
- `ensureEquipped(nameOrId)` *(Bool)*: Equips item if not already equipped.
- `isEquipped(nameOrId)` *(Bool)*: Returns `true` if item is equipped.
- `bankAll(exclude?)`: Deposits all unequipped, non-temporary items into bank.
- `bankAllAcItems(exclude?)`: Deposits unequipped AC-tagged items into bank (free storage).
- `unbankPreset(name)`: Withdraws all items from a hardfarm preset (e.g. `"vhl"`, `"lr"`).
- `unbankAllNonAcItems(exclude?)`: Withdraws non-AC items back into backpack.
- `bankAcAndUnbankNonAc(exclude?)`: Banks AC items, then unbanks non-AC items.
- `isBanking()` / `isUnbanking()` *(Bool)*: Returns `true` while bank transfer queue is active.
- `buyItem(shopId, nameOrId, qty = 1)`: Loads shop and purchases item by name or ItemID (throttled to 1/sec).
- `buyItems(list, gapMs = 1000)` *(Int)*: Queues multiple purchases safely.
- `sellItem(nameOrId, qty = 1)`: Sells item to shop by name or ItemID.

---

### Drops & Loot
- `acceptAllDrops(enabled? = true)`: Automatically accepts all drops as they appear. Also supports assignment: `acceptAllDrops = true;`
- `acceptAcDrops(enabled? = true)`: Automatically accepts AC-tagged drops only. Also supports assignment: `acceptAcDrops = true;`
- `getDrop(nameOrId)`: Picks up a specific drop by name or ItemID.
- `getDrops(target? = "all")`: Picks up pending drops (`"all"`, `"any"`, or array of names/IDs).
- `addBlacklist(nameOrId)`: Blocks item from drop queue by name or ItemID.
- `removeBlacklist(nameOrId)`: Removes item from blacklist.
- `isBlacklisted(nameOrId)` *(Bool)*: Checks if item is blacklisted.
- `clearBlacklist()`: Clears drop blacklist.
- `sellBlacklist()`: Sells all owned blacklisted items.

---

### Server Boosts
AQW tracks active server boost durations in seconds (`iBoostG`, `iBoostCP`, `iBoostRep`, `iBoostXP`).
- `isBoostActive(type)` *(Bool)*: Checks if a boost is active (`"gold"`, `"class"`, `"rep"`, `"xp"`).
- `getBoostRemaining(type)` *(Int)*: Returns remaining boost duration in seconds.
- `useBoost(nameOrId)` *(Bool)*: Uses a boost consumable from inventory by item name, ID, or boost type keyword (e.g. `useBoost("gold")`).
- `autoBoost(type, enabled? = true)`: Automatically consumes matching inventory boosts when the active duration reaches 0.

---

### Auras & Client Memory Maintenance
- `hasAura(name)` *(Bool)*: Returns `true` if aura is active on your character.
- `getAuraStacks(name)` *(Float)*: Returns current aura stack count.
- `getAuraRemaining(name)` *(Float)*: Returns remaining aura duration in seconds.
- `cleanExpiredAuras()` / `cleanAuras()` *(Int)*: Instantly purges expired (`aura.e == 1`) and orphan aura entries from player and monster aura trees.
- `autoCleanAuras(enabled? = true)`: Toggles automated 5-second background aura cleanup (enabled by default).

---

### Character Status & Factions
- `hp()` / `getHp()` *(Int)*: Current HP.
- `maxHp()` / `getMaxHp()` *(Int)*: Maximum HP.
- `mp()` / `getMp()` *(Int)*: Current MP.
- `maxMp()` / `getMaxMp()` *(Int)*: Maximum MP.
- `gold()` / `getGold()` *(Int)*: Current gold.
- `level()` / `getLevel()` *(Int)*: Character level.
- `username()` / `getUsername()` *(String)*: Player username.
- `isAlive()` *(Bool)*: Returns `true` if character is alive (`hp > 0`).
- `isInCombat()` *(Bool)*: Returns `true` if currently in combat.
- `isMember()` *(Bool)*: Returns `true` if account has active membership.
- `factionRank(name)` / `getFactionRank(name)` *(Int)*: Rank in specified faction (e.g. `"Falcon"`).

---

### Execution Control, Logging & System
- `log(message)`: Outputs timestamped message to `api.log`, console, and game chat. Repeated identical messages are collapsed.
- `notify(message)`: Displays on-screen notification card.
- `warn(message)` / `error(message)`: Warning and error console logs.
- `msg(message)`: Logs to both file/console and shows an on-screen notification.
- `sleep(ms)`: Pauses script execution for specified milliseconds.
- `stop()`: Halts script, drops combat, and invokes `onStop()`.
- `sendPacket(packet)`: Sends raw string packet to server.
- `clearLog()`: Clears `api.log`.

---

## 5. Hardfarm Item Presets

AQW routes newly dropped items directly into your Bank if any quantity exists in your Bank. Always call `unbankPreset("name")` in `onStart()` to ensure items land in your backpack for turn-ins.

| Preset Key | Display Name | Count | Key Items Included |
|---|---|---|---|
| `"vhl"` | Void Highlord | 32 | Roentgeniums, Crystals A & B, Elders' Blood, Totems, Blood Gems, Diamonds |
| `"lr"` | Legion Revenant | 24 | Legion Fealty 1, 2, 3, 4, Spellscrolls, Exalted Crowns, Legion Tokens |
| `"nulgath"` | Nulgath Nation | 27 | Diamonds, Gems, Vouchers, Blood Gems, Totems, Unidentified items |
| `"blod"` | Blinding Light of Destiny | 54 | Spirit Orbs, Loyal Spirit Orbs, Brilliant Aura, Blinding Auras, Mine Crafting metals |
| `"awe"` | Blade & Gear of Awe | 47 | Blade of Awe pieces, Stonewrit, Handle, Hilt, Blade, Runes |
| `"legion"` | Undead Legion | 25 | Legion Tokens, Dage's Favor, Diamond Tokens of Dage, Dark Token, Soul Gems |
| `"dot"` | Dragon of Time | 49 | Dragon of Time artifacts, hourglasses, cross-game boss drops |
| `"ynr"` | Yami no Ronin | 28 | Yokai Sword Scroll, Platinum Medals, Folded Steel |
| `"vdk"` | Verus DoomKnight | 44 | Verus DoomKnight traces, doom souls, dark energy |
| `"cav"` | Chaos Avenger | 10 | Chaos Avenger fragments, Champion Lionfang, insignias |
| `"arcana_invoker"` | Arcana Invoker | 29 | Major Tarot Cards, Arcana shards, Fool, World, Death cards |
| `"archmage"` | ArchMage | 27 | ArchMage books, tomes, celestial scrolls, elemental ribbons |
| `"nsod"` | Necrotic Sword of Doom | 29 | Void Auras, Necrotic Sword blades, Energized hilts, Bones from the Void |
| `"sdka"` | Sepulchure's DoomKnight Armor | 40 | Dark Spirit Orbs, Corrupt Spirit Orbs, Doom Auras, Accursed Ores |
| `"darkon"` | Darkon & Astravia | 20 | Banana, Teeth, Lasers, Receipts, Sukra, Suki, Wheel of Fortune items |
| `"sow"` | Shadows of War | 18 | Darkness & Fire Fragments, Malgor Insignias, Shadow Flame, Elemental Orbs |
| `"hollowborn"` | Hollowborn | 27 | Hollow Soul, Hollowborn DoomKnight items, Bone Dust, Radiant catalysts |
| `"ultras"` | Ultra Boss Insignias | 18 | Weekly insignias: Dage, Nulgath, Drago, Darkon, Speaker, Tyndarius |
| `"forge"` | Forge Enhancements | 32 | Praxis, Forge Medals, Caelestite, Void Auras, Ascended items |
| `"dailies"` | Daily Quest Reagents | 36 | Crypto Tokens, Shadow Shield, Dage Scroll Fragment, Elder's Blood, Sparagmos |
| `"kings_echo"` | King's Echo | 19 | Echoes of King, ancient tokens, quest requirements |

---

## 6. Subsystem Namespaces Reference

For deep state inspection or specialized management, subsystems are accessible via first-class namespaces:

### `player.*`
`player.hp`, `player.maxHp`, `player.mp`, `player.maxMp`, `player.gold`, `player.level`, `player.isAlive`, `player.isInCombat`, `player.className`, `player.rest()`, `player.hasAura(name)`, `player.isBoostActive(type)`, `player.getBoostRemaining(type)`, `player.useBoost(nameOrId)`, `player.setAutoBoost(type, enabled)`

### `combat.*`
`combat.startAuto()`, `combat.startSmart()`, `combat.startCustom(rotation)`, `combat.useSkill(index)`, `combat.canUseSkill(index)`, `combat.stopCombat()`, `combat.ensure(smart)`

### `map.*`
`map.jump(cell, pad, force, autoCorrect)`, `map.ensure(name, cell, pad)`, `map.ensureHouse()`, `map.isHouse()`, `map.walkThroughWalls(enabled)`, `map.skipCutscenesNow()`, `map.getMapItem(id)`

### `quests.*`
`quests.load(id)`, `quests.accept(id)`, `quests.complete(id, choice)`, `quests.ensureComplete(id, choice)`, `quests.canComplete(id)`, `quests.hasBeenCompleted(id)`, `quests.isUnlocked(id)`, `quests.isAccepted(id)`

### `inventory.*` / `bank.*`
`inventory.hasItem(name, qty)`, `inventory.getItemCount(name)`, `inventory.getQuestQuantity(name)`, `inventory.equip(name)`, `inventory.bankAll(exclude)`, `inventory.unbankPreset(name)`, `inventory.isBanking`, `inventory.isUnbanking`

### `drop.*`
`drop.acceptAllDrops(enabled)`, `drop.acceptAcDrops(enabled)`, `drop.getDrop(name)`, `drop.acceptPendingDrops(names)`

### `shop.*`
`shop.loadShop(id)`, `shop.buyItem(name, qty)`, `shop.buyItems(list, gapMs)`, `shop.sellItem(name, qty)`, `shop.getPendingBuyCount()`, `shop.clearBuyQueue()`

### `monster.*`
`monster.getByCell(cell)`, `monster.isMonsterAliveInCell(cell)`, `monster.sortByLowestHp(monsters)`, `monster.getBestMonsterTargetInCell(cell, nameOrId)`

### `aura.*`
`aura.has(name, target)`, `aura.getStacks(name, target)`, `aura.getRemaining(name, target)`, `aura.cleanExpiredAuras()`, `aura.autoClean`, `aura.startAutoClean(intervalMs)`, `aura.stopAutoClean()`

### `api.*` / `bot.*`
Direct root reference to the full underlying engine (`api.player`, `api.combat`, `api.map`, `api.quest`, `api.inventory`, etc.).

---

## 7. Essential Rules & Best Practices

1. **Never use blocking `while` loops.** ActionScript 3 runs on a single UI thread. A `while (!hasItem(...))` loop freezes the client and causes a crash. Let `onTick()` do the polling.
2. **Always use numeric Quest IDs for quests (`quest(1234)`, `complete(1234)`).** The game server packet strictly requires numeric IDs to request quests from the server. Using IDs prevents network desync and guarantees the script can verify quests from anywhere (including your house on startup).
3. **Use readable names for monsters and items.** Write `hunt("Dark Makai", "Dark Makai Defeated", 50)` instead of memorizing item IDs.
4. **Never sum container counts.** Do NOT write `getTempQuantity(item) + getInventoryQuantity(item)`. Use `getQuestQuantity(item)` — it is de-duplicated across backpack, temp items, and quest trees.
5. **Always unbank farm presets on start.** If an item exists in your bank, AQW routes newly dropped stacks directly into your bank, preventing quest turn-ins from detecting them.
6. **Always guard quest actions with early returns.** Write `if (!hunt(...)) return;` so the tick loop yields while combat is ongoing.
7. **Always finish scripts safely.** End scripts by calling `ensureHouse(); stop();`.

---

## 8. AI Script Generation Prompting Guide

When prompting an AI assistant to generate new `.hxs` scripts, copy and paste this system prompt:

```markdown
Generate an AQW HScript (.hxs) bot script following these strict requirements:
1. Always implement function onStart(), function onTick(), and function onStop().
2. Use clean top-level functions (quest, hunt, mapItem, complete, ensureMap, ensureHouse, hasItem, equipLoadout, stop, log). Do NOT use bot. or map. prefixes.
3. Always use numeric Quest IDs for quests (e.g. quest(2239)), and readable names for monsters and items (e.g. hunt("Sneak", "AQ Dimension Key", 1)).
4. For saga/story quests, use the deterministic Step-by-Step pattern:
   if (quest(QUEST_ID, "mapname")) {
       if (!hunt("Monster Name", "Drop Name", QTY)) return;
       if (!mapItem(ITEM_ID, "Item Name", QTY)) return;
       complete(QUEST_ID);
       return;
   }
5. For multi-quest storylines, add the safe house verification check on startup:
   if (!checkedProgress) {
       if (!isHouse()) { ensureHouse(); return; }
       if (!ensureQuestsLoaded([ID1, ID2, ...])) return;
       checkedProgress = true;
   }
6. For end-game reagent farming, call unbankPreset("name") in onStart().
7. Never write blocking while loops or Thread.sleep.
8. On script completion or in onStop(), always call ensureHouse().
```
