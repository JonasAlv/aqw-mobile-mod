# AQW Haxe Scripting API Guide (.hxs)

Welcome to the official scripting guide for the AQW Client Mod. Scripts are written in **HScript** (`.hxs` files) — a lightweight, dynamic scripting language with standard JavaScript/ActionScript 3 syntax executing live inside the client engine.

---

## The Default Scripting Standard (Core Primitives + Namespaces)

Our scripting architecture combines the best of both worlds:
1. **Clean, top-level DSL primitives** for all primary botting actions (`quest`, `hunt`, `mapItem`, `complete`, `ensureMap`, `ensureHouse`, `hasItem`, `equipLoadout`, `stop`, `log`). No unnecessary prefixes needed for 99% of code.
2. **First-class object namespaces** (`player`, `combat`, `map`, `quests`, `inventory`, `bank`, `drop`, `shop`, `monster`, `aura`, `enhancement`, `blacklist`, `api`, `bot`) for advanced state queries and subsystem control.

Every top-level name is a plain global — no imports, no prefixes. The full list is in [Top-Level Primitives Quick Reference](#top-level-primitives-quick-reference).

### Minimalist Example:
```javascript
// Hunt 10 Possessed Armor in ShadowBattleon
function onStart() {
    log("Starting farm routine...");
    acceptAllDrops();
    equipLoadout("farm");
    join("shadowbattleon");
}

function onTick() {
    ensureMap("shadowbattleon");
    hunt("Possessed Armor", 10, stop);
}

function onStop() {
    log("Routine complete.");
    ensureHouse();
}
```

---

## Table of Contents
1. [Script Lifecycle Hooks](#script-lifecycle-hooks)
2. [Safe House Startup Pattern (Crucial for Sagas)](#safe-house-startup-pattern-crucial-for-sagas)
3. [The Deterministic Step-by-Step Quest Pattern](#the-deterministic-step-by-step-quest-pattern)
4. [Top-Level Primitives Quick Reference](#top-level-primitives-quick-reference)
5. [Subsystem Namespaces (`player`, `aura`, `shop`, etc.)](#subsystem-namespaces)
6. [Combat & Hunting](#combat--hunting)
7. [Drops, Inventory & Banking](#drops-inventory--banking)
8. [Bulk Purchasing](#bulk-purchasing)
9. [Auto Attack (`autoattack`)](#auto-attack-autoattack)
10. [Rate Limits](#rate-limits)
11. [Scripting Architectural Patterns](#scripting-architectural-patterns)
12. [AI Script Generation Guide](#ai-script-generation-guide)

---

## Script Lifecycle Hooks

Every `.hxs` script defines standard lifecycle hooks called by the engine:

| Hook | When it executes | Common Usage |
|---|---|---|
| `onStart()` | Executed **once** when the script starts | Set drop filters (`acceptAllDrops()`), equip loadouts, initialize state flags |
| `onTick()` | Executed **periodically** (~100ms) | Main routine (hunting, checking quests, verifying map position) |
| `onStop()` | Executed **once** when script is stopped | Safe exit (e.g. `ensureHouse()`), final cleanup, logging |
| `onPacket(packet)` | Executed on every incoming server packet | Custom packet sniffing, rare event listening |
| `onZoneEntered(zone)`| Executed on map/cell transfer | Zone buffs or custom cutscene triggers |
| `onQuestUpdated(id)` | Executed when a quest objective updates | Progress logging |
| `onInventoryChanged(item)`| Executed when items are added/removed | Inventory tracking |

---

## Safe House Startup Pattern (Crucial for Sagas)

When running multi-chapter sagas (like the *13 Lords of Chaos*), scripts should **never** check quest completion milestones while standing in hostile monster territory. Monsters will aggro, interrupt map transitions, or cause quest status packets to desync.

**The Solution:** Teleport to your private house on startup, safely load the chapter's quest list from the server, verify your progress, and only then teleport to the active quest.

```javascript
var checkedProgress = false;

function onStart() {
    checkedProgress = false;
    acceptAllDrops();
    setSkipCutscenes(true);
    equipLoadout("farm");
}

function onTick() {
    // 1. Initial safe house check to verify quest milestones
    if (!checkedProgress) {
        if (!isHouse()) {
            ensureHouse();
            return;
        }
        // Load all chapter quest IDs from server
        if (!ensureQuestsLoaded([2376, 2377, 2378, 2379, 2380, 2381])) {
            return;
        }
        checkedProgress = true;
        log("Milestone progress verified at house. Resuming storyline...");
    }

    // 2. Storyline execution begins...
}
```

---

## The Deterministic Step-by-Step Quest Pattern (Best Method to Prevent Bugs)

> [!IMPORTANT]
> **Step-by-step scripting is the gold standard and best method to use across all `.hxs` scripts.**
> In asynchronous game botting, monolithic macros or fire-and-forget loops cause monster lock-ins, cell jump cancellations, desynced turn-in packets, and endless loops. The **Deterministic Step-by-Step Pattern** completely eliminates these bugs by transforming each quest objective into an atomic, verified gate.

In earlier botting paradigms, macro functions like `storyKillQuest()` tried to automatically guess which monster dropped which requirement using fuzzy name heuristics. On hybrid quests (requiring **both** map items and monster drops), this caused infinite loops and turn-in errors.

With the **Deterministic Step-by-Step Pattern**, your script executes as a clean state machine where every line is a guarded condition:

```javascript
// Quest 2379: Bolster the Elements (Hybrid: 2 Map Items + 2 Monster Drops)
// Both mapItem and hunt follow the consistent (Target, Item, Qty) convention!
if (quest(2379, "aqlesson")) {
    if (!mapItem(1470, "Light of Hope Acquired", 3)) return;
    if (!mapItem(1471, "Tears of Joy Acquired", 3)) return;
    if (!hunt("Eternite Ore", "TimeSpark Acquired", 3)) return;
    if (!hunt("Water Elemental", "Shadows Acquired", 3)) return;
    complete(2379);
}
```

### Why this pattern guarantees bug-free execution:
1. **Atomic Progression with `return`:**
   - While an objective is in flight (walking to a cell, clicking a map item, or fighting a monster), the function returns `false`.
   - The trailing `return;` immediately exits `onTick()`, cleanly yielding control back to the game engine for that tick (~100ms).
   - This prevents race conditions where the script tries to jump cells or talk to NPCs while still in combat or mid-transfer.
2. **Zero Target-Lock Contamination:**
   - Because only one step runs at a time, `hunt()` locks onto exactly one target monster and releases the lock as soon as the target quantity is met. When the script advances to the next step, there are no lingering monster locks or target filters.
3. **`quest(questId, mapName)` acts as an automatic skip gate:**
   - If the quest was already completed (`isCompletedBefore(questId)`), it returns `false` immediately, skipping the entire block in under 1 millisecond.
   - If not yet completed, it automatically joins `mapName`, accepts the quest, and returns `true` to enter the step sequence.
4. **`mapItem(itemId, item, qty)` tracks exact inventory:**
   - Checks inventory directly for `item` $\ge$ `qty`. Gathers items respecting server rate limits (1500ms delay) and returns `true` once acquired.
5. **`hunt(monster, item, qty)` guarantees clean combat:**
   - Navigates to the monster's cell, activates your equipped rotation, and checks inventory for `item` $\ge$ `qty`. Returns `true` once the items are in your bag.
6. **`complete(questId)` safely finalizes the quest:**
   - Safely stops combat, sends the turn-in request, verifies server completion, and clears cached story state.

---

## Top-Level Primitives Quick Reference

These functions are available everywhere in `.hxs` files without any object prefix.

### Navigation & Maps
- `ensureMap(mapName, cell?, pad?)` *(Bool)*: Ensures you are on `mapName` and cell. Drops combat stealthily before transferring if in combat. Automatically routes `"house"` to your personal house.
- `ensureHouse()` *(Bool)*: Safely drops combat and teleports to your private house. Returns `true` once loaded.
- `join(mapName, cell?, pad?)`: Direct map transfer.
- `joinHouse(username?)`: Direct house transfer.
- `ensureCell(cell, pad?)` *(Bool)*: Ensures avatar is in the specified cell on current map.
- `jump(cell, pad?, autoCorrect? = true)`: Jumps to specified cell and pad. Automatically verifies active room pads on the Flash timeline and auto-corrects missing or invalid pads (`requested` -> `"Left"` -> `"Spawn"` -> `first valid pad`) to prevent getting stuck at `(0, 0)`.
- `jumpCorrect(cell, pad?)`: Forces an immediate cell jump with guaranteed live pad auto-correction.
- `autoCorrectJump(enabled?)` *(Bool)*: Gets or toggles live jump auto-correction globally (defaults to `true`).
- `getValidCellPads()` *(Array<String>)*: Returns active `Pad_\d+` symbols verified on the current cell timeline.
- `getCellPads()` *(Array<String>)*: Returns valid pads for the current cell (with fallback to naming heuristics).
- `getMapCells()` *(Array<String>)*: Returns all cell frame labels defined on the map timeline.
- `cell()` / `getCell()` *(String)*: Current avatar cell.
- `pad()` / `getPad()` *(String)*: Current avatar pad.
- `mapName()` / `getMapName()` *(String)*: Current map name.
- `isHouse()` *(Bool)*: Returns `true` if currently in your personal house.
- `isMap(name)` *(Bool)*: Returns `true` if on the specified map.
- `isCell(name)` *(Bool)*: Returns `true` if in the specified cell.
- `isLoaded()` *(Bool)*: Returns `true` if map is fully loaded.
- `setSkipCutscenes(enabled? = true)`: Enables/disables auto-skipping cutscenes on map joins.
- `isSkipCutscenes()` *(Bool)*: Returns `true` if auto-skipping is currently enabled.

### Player Status & Character Queries
All character properties are exposed as live, dynamic functions. Use these functions directly in conditionals rather than caching stale variables:
- `hp()` / `getHp()` *(Int)*: Current HP.
- `maxHp()` / `getMaxHp()` *(Int)*: Maximum HP.
- `mp()` / `getMp()` *(Int)*: Current MP / Mana.
- `maxMp()` / `getMaxMp()` *(Int)*: Maximum MP / Mana.
- `gold()` / `getGold()` *(Int)*: Current gold.
- `level()` / `getLevel()` *(Int)*: Current character level.
- `username()` / `getUsername()` *(String)*: Current player username.
- `isAlive()` *(Bool)*: Returns `true` if avatar is alive (`hp > 0` and `state > 0`).
- `isInCombat()` *(Bool)*: Returns `true` if avatar is currently engaged in combat.
- `isMember()` *(Bool)*: Returns `true` if account has an active membership.
- `factionRank(name)` / `getFactionRank(name)` *(Int)*: Current rank in the specified faction.
- `hasAura(name)` *(Bool)*: Returns `true` if the specified aura buff/debuff is active on your character.
- `getAuraStacks(name)` *(Float)*: Stack count of the specified aura.
- `getAuraRemaining(name)` *(Float)*: Remaining duration in seconds of the specified aura.

### Map Items (`mapItem` & `getMapItem`)
Two distinct functions — they are **not** aliases:
- **`mapItem(itemId, item, qty = 1, map?)`** *(Bool)*: **Recommended.** Follows the consistent `(Target, Item, Quantity)` structure identical to `hunt(mob, item, qty)`. Gathers map item until inventory contains `qty` of `item`.
- **`mapItem(itemId, qty = 1, item?, map?)`** *(Bool)*: Quantity-first overload (e.g. `mapItem(42, 5, "Dew Drop")`).
- **`mapItem(itemId, qty = 1)`** *(Bool)*: When quest requirements do not produce an inventory item (e.g. `mapItem(42, 5)` to click 5 times).
- **`ensureMapItem(itemId, ...)`** *(Bool)*: Alias for `mapItem`, all overloads.
- **`getMapItem(itemId)`** *(Bool)*: Interacts with a map item **once** (rate-limited to 1500ms), with no inventory check and no tracking. Takes exactly one argument — use `mapItem`/`ensureMapItem` when you need quantities.
- **`resetMapItems()`**: Clears the gathered-count history used by `mapItem`. Completing a quest does **not** clear it.

> [!NOTE]
> `mapItem` counts what it has already requested per **(item, map)** pair, so the same item required on two different maps is tracked separately. Use `resetMapItems()` if you need to force a re-gather.

### Combat & Hunting (`hunt`)
The `hunt()` function automatically resolves which cell the monster spawns in, transfers there, locks onto the target, and runs your combat rotation. It automatically detects the signature:
- **By Item Drop:**
  - `hunt(monster, item, qty = 1, callback?)` *(Bool)*: **Recommended.** Hunts monster until backpack or temporary inventory holds `qty` of `item` (e.g. `hunt("Frogzard", "Tooth", 6)`). Returns `true` when acquired.
  - `hunt(monster, item, qty, mmid, callback?)` *(Bool)*: Hunts a specific Map Monster ID (MMID) spawn until inventory holds `qty` of `item` (e.g. `hunt("Gorillaphant", "Gorillaphant Tusks", 6, 2)`). Ensures the bot navigates to that monster's cell and strictly locks onto that specific MMID.
- **By Kill Count:**
  - `hunt(monster, count, callback?)` *(Bool)*: Hunts monster by total kill count (e.g. `hunt("Frogzard", 10)` kills 10 Frogzards). Automatically counts monster deaths. Returns `true` when reached.
  - `hunt(monster, count, mmid, callback?)` *(Bool)*: Hunts a specific Map Monster ID (MMID) count (e.g. `hunt("Frogzard", 5, 2)`).
- **By Multi-Item Array:**
  - `hunt(monster, itemsArray, callback?)` *(Bool)*: Hunts monster until all requirements in array are collected:
    - String items with count: `hunt("Mob", ["Item A:10", "Item B:5"])`
    - Array pairs: `hunt("Mob", [["Item A", 10], ["Item B", 5]])`
- **Continuous / Unbounded:**
  - `hunt(monster)` *(Bool)*: Hunts monster indefinitely without count constraints.
- **Wildcard Targeting:**
  - `hunt("*", 5)`: Kills any 5 monsters in the current cell.
  - `hunt("*", "Item", 3)`: Attacks any monster until 3 items are acquired.
- **Aliases & Helpers:**
  - `kill(...)` *(Bool)*: Direct alias for `hunt(...)` supporting all the same overloads.
  - `huntItem(monster, item, qty = 1, map?)` *(Bool)*: Navigates to `map`, checks inventory, and hunts for item.
  - `huntMonster(monster, kills = 1, map?)` *(Bool)*: Navigates to `map` and hunts by kill count.
- `stopCombat()`: Drops target, halts auto-attack, and stealthily drops aggro in-place.
- `ensureCombat(smart? = true)`: Ensures combat engine is active.
- `equipLoadout("farm" | "solo" | "support")` *(Bool)*: Equips predefined class, gear, and combat rules.
- `attack(monster)`: Targets and attacks monster.

> [!NOTE]
> **What is a `callback`?**
> A callback is an optional function (e.g. `function() { log("Done!"); }`) passed at the end of `hunt(...)` or `kill(...)` that executes once when the hunt condition is satisfied (all requested items are gathered or kill count is met).
>
> In typical `.hxs` scripts using the `onTick()` loop, **callbacks are usually unnecessary** because `hunt()` returns `false` while fighting and `true` when finished:
> ```haxe
> if (!hunt("Frogzard", "Frogzard Tooth", 6)) return;
> // Code below runs automatically on the tick the hunt finishes:
> complete(1234);
> ```
> Use a callback when you want to trigger one-time event logic or specialized notifications at the moment of completion:
> ```haxe
> hunt("Gorillaphant", "Gorillaphant Tusks", 6, 2, function() {
>     log("Tusks completed from MMID 2!");
> });
> ```

### Quests & Storyline
- `quest(questId, mapName?)` *(Bool)*: Skips block if quest is already completed; otherwise ensures map, accepts quest, and returns `true`.
- `complete(questId, choice?)` *(Bool)*: Turns in quest (with optional choice reward ID or name). Returns `true` on completion.
- `hasBeenCompleted(questId)` / `isCompletedBefore(questId)` *(Bool)*: Returns `true` if quest has already been finished.
- `canComplete(questId)` / `isQuestComplete(questId)` *(Bool)*: Returns `true` if all turn-in requirements are satisfied.
- `isQuestUnlocked(questId)` / `isUnlocked(questId)` *(Bool)*: Returns `true` if quest is unlocked for your character.
- `getMissingRequirements(questId)` *(Array)*: Returns the outstanding requirement objects for a quest.
- `ensureQuestsLoaded(questIds)` *(Bool)*: Pre-loads quest definitions from the server. Accepts an array or a single ID.
- `areQuestsLoaded(questIds)` *(Bool)*: Returns `true` once every listed quest definition has loaded.
- `loadQuest(questId)` / `loadQuests(questIds)`: Fetches quest definitions without accepting.
- `acceptQuest(questId)`: Accepts an already-loaded quest.
- `ensureQuest(questId)` *(Bool)*: Ensures the quest is loaded and accepted. Returns `true` if the quest is **already completed** — a completed quest can never be re-accepted, so treat `true` as "nothing left to do here" and never loop on `false`.
- `ensureAccept(questId)` *(Bool)*: Same as `ensureQuest`.
- `ensureComplete(questId, choice?)` *(Bool)*: Alias for `complete`.
- `completeQuest(questId, choice?)`: Fire-and-forget turn-in, no completion verification.
- `autoQuest([ids])`: Runs background auto-questing (acceptance, requirement checking, turn-in).
- `isAutoQuestRunning()` *(Bool)*: Returns `true` while background auto-questing is active.
- `stopAutoQuest()`: Stops background auto-questing.
- `storyKillQuest(id, map, monster)` *(Bool)*: Macro kill quest helper (supports string or array of monsters).
- `storyMapItemQuest(id, map, itemIds, amount? = 1)` *(Bool)*: Macro map item quest helper.
- `storyChainQuest(id, map?)` *(Bool)*: Chain turn-in quest helper (dialogs, cutscene quests).
- `resetStoryData()`: Clears all per-run script state, including map-item counts. The engine calls this for you on start and stop.

### Inventory, Drops & Banking
- `hasItem(itemName, qty? = 1)` *(Bool)*: Checks regular and temporary inventory for item quantity.
- `getItemCount(itemName)` *(Int)*: Returns regular inventory count.
- `getQuestQuantity(itemName)` *(Int)*: Returns count checking backpack, temp inventory, and quest tree.
- `getInventory()` *(Array)*: Returns all inventory items.
- `getBankItems()` *(Array)*: Returns all bank items.
- `getBankQuantity(itemName)` *(Int)*: Stack size for one item in the bank, `0` if not banked.
- `getInventoryQuantity(itemName)` *(Int)*: Stack size in the backpack only, `0` if absent.
- `isQuestAccepted(questId)` *(Bool)*: Whether a quest is in progress or queued for accept.

#### Temporary (Quest) Items

Quest items live in a **third** container, `avatar.tempitems`, which is neither the backpack nor the bank. The game splits them with `bTemp`: an `addItems` packet entry with `bTemp != 0` goes to `addTempItem` rather than `addItem`. Because they are a separate array, `getInventory()` and `getBankItems()` never report them.

- `getTempItems()` *(Array)*: All temp items.
- `getTempQuantity(itemName)` *(Int)*: Stack size in the temp container.
- `hasTempItem(itemName, qty? = 1)` *(Bool)*: Whether the temp container holds enough.

#### Locating an Item

- `getItemLocation(itemName)` *(String)*: `"temp"`, `"inventory"`, `"house"`, `"bank"`, or `""` when absent.
- `findItem(itemName)` *(Object)*: `{item, id, name, quantity, location}` or `null`.

`quantity` from `findItem` is the count **in that one container**, not a total across all of them — a caller acting on it needs to know what the specific container holds. `getItemLocation` checks `temp` first, so a quest temp item and a banked copy of the same ItemID resolve to `"temp"` rather than `"bank"`.

#### Never sum the container readers

`getQuestQuantity` is the only **de-duplicated** reading. It inspects the backpack, the temp container *and* `world.invTree`, and guards every match with a `countedNames` set keyed by ItemID, so an item visible in more than one place is still counted once.

The container readers are **not** additive:

```haxe
getTempQuantity("Shadow Hunt Medal") + getInventoryQuantity("Shadow Hunt Medal")   // WRONG - can double count
getQuestQuantity("Shadow Hunt Medal")                                               // RIGHT - counted once
```

Use `getQuestQuantity` for any "do I have enough" decision, and the container readers plus `getItemLocation`/`findItem` only when you specifically need to know *where* the item is. `scripts/ShadowBattleon_TempItem_Tracking.hxs` is a runnable diagnostic that reports all four readings side by side and flags the sum-vs-dedup mismatch.

#### Reset on Target Change

The **Reset** toggle in the Combat Mode Editor decides what happens to the rotation when you switch targets.

- **ON** — acquiring a new target restarts the combo from slot 0.
- **OFF** — the rotation keeps its position, so you resume mid-combo on the next mob.

This is per-mode and persists in `userSkills.json` as `resetComboOnTargetChange`. It can also be set in the mode text itself:

```
[MyClass : myMode]
mode = WaitForCooldown
timeout = 0
combo = 1 > 2 > 3 > 4
resetComboOnTargetChange = true
```

`getResetOnTargetChange([class], [mode])` returns the flag as stored, defaulting to the current class and active mode.

Two behaviours worth knowing:

- A target that **dies while still referenced** counts as a target change even though its `MonMapID` is unchanged, so ON does restart the rotation on death — and the engine stops trying to fight the corpse. Previously the identity check missed this case entirely.
- The global **custom rotation** (not a mode) always restarts on a new target; it has no mode config, so there is no flag to read. The toggle only affects mode-based rotations.

When the reset fires, the engine logs `Reset on target change: restarting combo from slot 0` so you can confirm it rather than inferring it from which skill came out.

#### Auto Attack (`autoattack`)

Whether a rotation lets the API fire Auto Attack. Three states per mode:

| Spelling | Meaning |
|---|---|
| omitted / `null` | **Inherit** — fall back to the class default, then to on |
| `true` | Mode turns Auto Attack on |
| `false` | Mode turns Auto Attack off |

**Precedence: the mode wins; the class object is only a default.** The mode is the more specific setting, so `autoattack` on a mode always outranks a class-level `autoattack`. A mode can therefore re-enable Auto Attack on a class whose own flag says off — the earlier order was inverted (class outranked mode) and left a class that turned it off unable to recover through any of its modes.

Resolution order, applied by both `modeHasAutoAttack` and `classHasAutoAttack`:
1. mode's own `autoattack`
2. class object's `autoattack`
3. `true` (Auto Attack on)

When it resolves on, the API owns Auto Attack through `SkillCaster.fireAutoAttack`. When it resolves off, nothing is sent and `world.cancelAutoAttack()` is not called — the game keeps whatever state it had.

#### Rate Limits

**Every timing value in the API lives in one file: `aqw-haxe-api/src/com/aqwapi/utils/ApiTimings.hx`.** Change a value there and it applies everywhere — the managers, the combat engine, and `rateLimit()` all read the same constant, so a too-short or too-long timer has exactly one place to fix.

AQW enforces server-side cooldowns on these actions. The managers already gate them and queue internally, so calling the `ensure*` forms is always safe. These are **not tuning knobs** — do not bypass them, or the server silently drops the action:

| Action | Interval | Constant |
|---|---|---|
| Quest accept / complete / turn-in | 1100ms | `ApiTimings.QUEST_ACTION_MS` (1000 server + 100 lag margin) |
| Bank / unbank transfer | 1100ms | `ApiTimings.BANK_ACTION_MS` |
| Shop load | 1500ms | `ApiTimings.SHOP_LOAD_MS` |
| Buy / Sell | 1000ms | `ApiTimings.SHOP_BUY_MS` / `SHOP_SELL_MS` |
| Map join | 2000ms | `ApiTimings.MAP_JOIN_MS` |
| Map item pickup | 2000ms | `ApiTimings.MAP_ITEM_MS` |
| Cell jump | 500ms | `ApiTimings.CELL_JUMP_MS` |

Combat-side values live in the same file: `COMBAT_TICK_MS` (100ms engine tick), `MIN_CAST_GAP_MS` (200ms shared by Auto Attack and the rotation), `COUNTER_WINDOW_MS` (default `[counter]` window), `TEMP_IGNORE_MS`, `CC_CHECK_CACHE_MS`, plus poll/settle delays (`SETTLE_MS`, `HOUSE_POLL_MS`, `BANK_LOAD_POLL_MS`, `QUEST_REFRESH_MS`, `ENHANCE_POLL_MS`, `EQUIP_TIMEOUT_MS`).

`rateLimit()` returns every value as an object, `rateLimitDump()` renders them as one log line, and `questActionCooldownMs()` returns just the quest one. All three read `ApiTimings` directly, so a script cannot read a stale copy.

Prefer `ensureAccept` / `ensureQuest` / `ensureComplete` over the raw `acceptQuest` / `complete`. The `ensure*` forms return `true` when the quest is already accepted, completed or still loading, so a polling loop terminates instead of re-requesting every tick and walking into the throttle.

#### Bulk Purchasing

`buyItem` throttles itself to one purchase per second and **silently discards** calls made inside that window. Looping over `buyItem` to buy several different things therefore buys the first and throws the rest away:

```haxe
for (name in ["50k", "25k", "10k"]) buyItem(shopId, name);   // buys ONE item
```

`buyItems` queues them instead and drains one per `gapMs`, so every entry is actually sent:

```haxe
buyItems([
  {item: "50k Gold Voucher", quantity: 5},
  ["25k Gold Voucher", 2],
  {name: "Stealth"}                  // quantity defaults to 1
], 800);                             // returns how many were accepted
```

Each entry is `{item, quantity}`, `[name, qty]`, or `{name}` / `{name, qty}`. Names are trimmed, `quantity`/`qty` below 1 becomes 1, numeric strings like `"7"` are accepted, and an entry with no usable name is rejected rather than queued as a broken purchase. Use `getPendingBuyCount()` to check progress and `clearBuyQueue()` to abandon the rest.

Note `shop.buyItem(itemName, qty)` takes a **name or ItemID** directly, whereas the top-level `buyItem(shopId, itemName, qty)` also loads the shop first.
- `equip(itemName)`: Equips weapon, armor, helm, cape, class, or pet.
- `isEquipped(itemName)` *(Bool)*: Returns `true` if the item is currently equipped.
- `ensureEquipped(itemName)` *(Bool)*: Equips the item if it is not already equipped; returns `false` on the tick it initiates the swap.
- `acceptAllDrops(enabled? = true)`: Automatically accepts all item drops as they appear. Also accepts plain assignment: `acceptAllDrops = true;`
- `acceptAcDrops(enabled? = true)`: Automatically accepts AC-tagged items only. Also accepts plain assignment: `acceptAcDrops = true;`
- `getDrop(itemName)`: Picks up a specific drop.
- `getDrops(target?)`: Accepts pending drops. Defaults to all; accepts `"any"`/`"*"` or an array of item names.
- `buyItem(shopId, itemName, qty? = 1)`: Loads shop and buys item.
- `buyItems(list, gapMs? = 1000)` *(Int)*: Queues several purchases, returning how many were accepted. See [Bulk Purchasing](#bulk-purchasing).
- `getPendingBuyCount()` *(Int)*: Purchases still queued.
- `clearBuyQueue()`: Drops everything still queued.
- `bankAll(exclude?)`: Deposits all unequipped, non-temporary items into Bank.
- `bankAllAcItems(exclude?)`: Deposits all unequipped AC items into free bank storage.
- `unbankPreset(name)`: Unbanks all items from a hardfarm preset (e.g. `"vhl"`, `"lr"`, `"nulgath"`).
- `unbankAllNonAcItems(exclude?)`: Withdraws non-AC items back into backpack.
- `bankAcAndUnbankNonAc(exclude?)`: Banks AC items first, then withdraws non-AC items.
- `isBanking()` / `isUnbanking()` *(Bool)*: Returns `true` while bank transfer queue is active.

### Player Status
- `level()` *(Int)*: Current player level.
- `isMember()` *(Bool)*: Returns `true` if the account is a member.
- `factionRank(name)` / `getFactionRank(name)` *(Int)*: Returns the rank in the named faction (e.g. `"Falcon"`), `0` if none.

### Blacklist Management
- `addBlacklist(itemName)`: Blocks item from drop queue.
- `isBlacklisted(itemName)` *(Bool)*: Returns `true` if the item is blacklisted.
- `removeBlacklist(itemName)`: Un-blocks a single item.
- `clearBlacklist()`: Removes every blacklist entry.
- `sellBlacklist()`: Sells all owned blacklisted items.

### Execution Control & Logging
Scripts have **two output channels**, and picking the right one is what keeps the log readable:

| Call | Goes to | Use for |
|---|---|---|
| `log(msg)` | `api.log`, console, game chat | Progress your script reports repeatedly |
| `notify(msg)` | On-screen notification only | A one-off message you must not miss |
| `warn(msg)` / `error(msg)` | Log, console, chat, notification on error | Problems |

- `log(message)`: Timestamped message in `assets/api.log`, console, and game chat (if enabled).
- `notify(message)`: Shows an on-screen notification only — nothing is written to the log or chat.
- `msg(message)`: Logs **and** shows a notification. Convenient, but it is the one function that writes to both channels, so prefer `log()` for anything a loop can repeat.
- `warn(message)` / `error(message)`: Warning and error console logs. An uncaught script error also raises a notification and stops the script.
- `clearLog()`: Truncates `assets/api.log` to start fresh. Called automatically when a script starts.
- `copyLog()`: Copies `assets/api.log` content to system clipboard.
- `readLog()`: Reads string content of `assets/api.log`.
- `setChatLogging(enabled)`: Globally toggles API and script blue messages in game chat.
- `isChatLogging()` *(Bool)*: Returns whether game chat logging is currently active.
- `sleep(ms)`: Pauses script execution for specified milliseconds.
- `stop()`: Halts script, drops combat, and invokes `onStop()`.
- `resetHunt()`: Clears the current hunt target and counters without stopping the script.
- `sendPacket(packet)`: Sends raw game packet to server.

### The `[counter]` Rule

`[counter]` holds a combo slot until the **target has actually attacked us**. Built for riposte loops where a skill must only be spent in answer to an attack — most notably the Chrono ShadowHunter dodge rotation, where skill `3` consumes the dodge buff and therefore has to land *after* the mob swings, not before.

Detection reads the **server's own hit packet** (`sar` / `sars`, or `sara` / `sarsa` carried on the periodic `ct` tick) rather than our HP or the mob's animation. So a dodged or missed swing still counts, and the timing is the exact moment the server resolved the attack. An HP-delta trigger would only fire on swings that actually connected, which is the opposite of what a riposte needs.

#### Hard lock vs timed gate

This is the important distinction, and it is decided entirely by whether a time value is present:

| Spelling | Behaviour |
|---|---|
| `[counter x2]` | **HARD LOCK**, opens only after **2** attacks have landed. `x3`, `x4`, ... work the same way. |
| `[counter x2=miss]` | Hard lock, opens after 2 **missed** swings specifically |
| `[counter]` | **HARD LOCK.** Waits indefinitely for the target's first attack and never expires. The rotation **holds the slot** and retries every tick — it will not skip past it, and the mode-level `timeout` cannot skip it either. |
| `[counter <= 1.5s]` | Ordinary **timed gate**. Passes only while an attack landed within the last 1500ms. A false result advances the rotation like any other unmet condition, and `timeout` applies. |
| `[counter <= 1500]` | Same, in milliseconds |
| `[counter=miss]` | Hard lock, but only a **miss** opens it |
| `[counter=miss <= 2s]` | Timed gate, misses only |
| `[hit]`, `[attacked]`, `[mobattack]` | Aliases for `[counter]` (hard lock) |

Filter types: `hit`, `crit`, `miss`, `dodge`, `parry`, `block`, `none` — all from the server's own resolution enum.

**Why `xN` and not `=N` for the count:** `=` followed by digits has always meant a millisecond window, so `[counter=1500]` is a 1500ms gate. Letting `=` also carry a count would silently reinterpret every existing window as "wait for 1500 hits" with no error. `x` cannot collide — no resolution type or alias begins with it. If both a count and a window are given, the count governs, since "wait for N" is the stricter condition.

A hard lock is **edge-triggered**: one mob attack opens exactly one `[counter]` slot. When the locked skill fires, that attack is marked spent, so the next `[counter]` slot in the rotation waits for the mob's *next* swing rather than replaying the same one. A level-triggered check ("has it ever happened") latches true after the first hit and would make `3[counter]` chain back-to-back with no mob attack in between.

**Arming delay.** A hard lock also ignores attacks that land within `ApiTimings.COUNTER_ARM_DELAY_MS` (300ms) of your last cast. Mobs frequently swing in the same instant you cast the arm skill — a dodge buff, say — and reacting to that instant spends the riposte before the buff can resolve, so the hit the dodge *actually* answered is the one you never reply to. The cutoff is recomputed only when you cast, so an ignored early hit stays ignored rather than being picked up once the arm window passes. Change the delay in one place: `ApiTimings.COUNTER_ARM_DELAY_MS`.

Use a bare `[counter]` when the skill must **never** be wasted; use a window when missing the window should simply move on. A hard lock waits forever, so it only releases on an actual attack or on losing the target — if you put one in a long rotation, everything after it waits behind it by design.

When a hard lock is holding, the engine logs it (throttled) so a stalled rotation is visible rather than looking like a skill that never fires.

**Timing and GCD.** A `[counter]` slot can go true while a global cooldown is still running. The engine then waits out the GCD and casts on the first free moment — it does *not* cancel, and it does *not* discard the reaction. Two consequences worth knowing:

- There is no desync. Boss and mob attack timing is server-driven and is unaffected by when you cast, so a late riposte cannot shift a boss's next attack. What you get is **variable latency**: the riposte lands between roughly 100ms and 900ms after the attack resolves, depending on where you were in GCD when it landed. That is jitter, not drift, and no cumulative offset builds up.
- Detecting the attack during GCD is still the correct behaviour. Discarding the reaction because GCD was active would turn a slightly-late riposte into no riposte at all.

The combo for the CSH dodge loop becomes exactly the shape you described:

```haxe
1 > 2 > 3[counter] > 2 > 3[counter] > 4
```

`2` arms dodge, `3` waits for the mob to swing before riposting, `4` drops the enemy hit rating once you are out of mana. The rule reports `false` when there is no target, so a riposte can never fire after the mob dies or drops.

> [!NOTE]
> **Repeated identical log lines are collapsed automatically.** Consecutive identical messages within 2 seconds are written once, then summarised as `... (repeated N times)` once the burst goes quiet — so a `log()` inside a tight loop will not flood `api.log` or game chat. Only the count changes, never the wording, so nothing is silently lost.
>
> On-screen notifications are capped at 6 visible cards and a repeat of the message already on screen folds into a `(xN)` counter instead of stacking another copy. Cards grow to fit long text, and anything taller than a few lines scrolls in place instead of being cut off.

---

## Subsystem Namespaces

Specialized queries, deep player metrics, and manager controls are accessible via first-class namespaces:

### `player.*`
- `player.hp` / `player.maxHp` *(Int)*: Current and maximum health.
- `player.mp` / `player.maxMp` *(Int)*: Current and maximum mana.
- `player.gold` / `player.coins` *(Int)*: Current character gold.
- `player.ac` *(Int)*: Current AdventureCoins.
- `player.level` *(Int)*: Current character level.
- `player.isAlive` *(Bool)*: Character alive status.
- `player.isInCombat` *(Bool)*: Engaged in combat status.
- `player.isMember` *(Bool)*: Upgrade/membership status.
- `player.className` *(String)*: Equipped class name.
- `player.rest()`: Rests to recover HP and MP.
- `player.hasAura(auraName)` *(Bool)*: Returns `true` if player has aura.

### `aura.*`
- `aura.has(auraName, target? = "player")` *(Bool)*: Checks if player or target has aura.
- `aura.getStacks(auraName, target? = "player")` *(Float)*: Returns current stack count.
- `aura.getRemaining(auraName, target? = "player")` *(Float)*: Returns remaining seconds.

### `shop.*`
- `shop.loadShop(shopId)`: Loads shop from server.
- `shop.isShopLoaded` *(Bool)*: Shop loaded status.
- `shop.loadedShopId` *(Int)*: Currently active shop ID.
- `shop.buyItem(itemName, qty? = 1)`: Purchases item. Throttled to 1/sec; extra calls inside that window are dropped.
- `shop.buyItems(list, gapMs? = 1000)` *(Int)*: Queues several purchases, one per `gapMs`. Returns the accepted count.
- `shop.getPendingBuyCount()` *(Int)*: Purchases still queued.
- `shop.clearBuyQueue()`: Drops everything still queued.
- `shop.sellItem(itemName, qty? = 1)`: Sells item.

### `monster.*`
- `monster.getByCell(cellName)` *(Array)*: Returns all monsters spawned in cell.
- `monster.isMonsterAliveInCell(cellName)` *(Bool)*: Checks for living monsters in room.
- `monster.getMapMonsterNames()` *(Array<String>)*: Returns all monster names on the map.

### `combat.*`
- `combat.startAuto()`: Starts auto combat rotation.
- `combat.startSmart()`: Starts smart class-aware combat.
- `combat.startCustom(rotation)`: Starts custom rotation (e.g. `"1,2,3,4"`).
- `combat.useSkill(index)` *(Bool)*: Activates skill 1..4.
- `combat.canUseSkill(index)` *(Bool)*: Checks if skill is off cooldown and has sufficient mana.

### `enhancement.*`
- `enhancement.smartEnhance(pattern, level?)`: Enhances gear automatically.
- `enhancement.isForgeUnlocked(enhancementName)` *(Bool)*: Checks Forge quest unlocks.
- `enhancement.isAweUnlocked()` *(Bool)*: Checks Blade of Awe unlocks.

### `map.*`
- `map.jump(cell, pad?, force?, autoCorrect?)`: Moves to cell and pad with live timeline pad verification.
- `map.autoCorrectJump` *(Bool)*: Property to get/set live jump auto-correction.
- `map.getValidCellPads()` *(Array<String>)*: Array of active `Pad_\d+` timeline symbols.
- `map.getCellPads()` *(Array<String>)*: Room pads with heuristic fallback.
- `map.getMapCells()` *(Array<String>)*: Frame cell labels on the current map.
- `map.reload(pad?)`: Resets and reloads the current room cell.
- `map.getMapItem(itemId)` *(Bool)*: Low-level map item pickup.

### `api.*` / `bot.*`
Direct root reference to the full underlying AQW engine:
- `api.player`, `api.combat`, `api.map`, `api.quest`, `api.inventory`, `api.drop`, `api.shop`, `api.monster`, `api.aura`, `api.enhancement`, `api.transport`

---

## Drops, Inventory & Banking

### Hardfarm Item Presets (`unbankPreset`)
AQW routes newly dropped items directly into your Bank if any quantity exists in your Bank. This stalls bots indefinitely because turn-ins only check backpack inventory.

Always unbank your farm reagents in `onStart()` using built-in presets:
```javascript
function onStart() {
    acceptAllDrops();
    equipLoadout("farm");

    // 1. Bank all junk while preserving VHL materials:
    bankAll("vhl");

    // 2. Unbank all 32 VHL reagents so drops land in backpack:
    unbankPreset("vhl");

    join("tercessuinotlim");
}

function onTick() {
    // Wait until paced unbank queue finishes before fighting:
    if (isUnbanking()) return;

    // Farming continues...
}
```

#### Available Built-in Presets:
- `"nulgath"`: 27 core Nation materials (Diamonds, Gems, Vouchers, Blood Gems, Totems, Unidentified items).
- `"vhl"`: 32 Void Highlord reagents (Roentgeniums, Crystals A & B, Elders' Blood, Totems).
- `"lr"`: 24 Legion Revenant reagents (LF1, LF2 cohorts, LF3, Spellscrolls, Legion Tokens).
- `"dot"`: 49 Dragon of Time artifacts and boss drops.
- `"ynr"`: 28 Yami no Ronin materials.
- `"vdk"`: 44 Verus DoomKnight traces and souls.
- `"cav"`: 10 Chaos Avenger fragments and insignias.
- `"archmage"`: 27 ArchMage books, tomes, and scribing materials.
- `"nsod"`: 29 Necrotic Sword of Doom void auras, hilts, and blades.
- `"sdka"`: 40 Sepulchure's DoomKnight Armor dark spirit orbs and doom auras.

---

## Scripting Architectural Patterns

### Pattern 1: Complete Saga Chapter (House Safe Start + Step-by-Step)
```javascript
// Script: 10_Iadoa_TheSpan.hxs
var checkedProgress = false;

function onStart() {
    checkedProgress = false;
    if (isCompletedBefore(2519)) {
        log("Chapter already completed!");
        stop();
        return;
    }
    acceptAllDrops();
    setSkipCutscenes(true);
    equipLoadout("farm");
}

function onTick() {
    if (isCompletedBefore(2519)) {
        log("Chapter finished!");
        stop();
        return;
    }

    // Safe house milestone check
    if (!checkedProgress) {
        if (!isHouse()) {
            ensureHouse();
            return;
        }
        if (!ensureQuestsLoaded([2239, 2240, 2241, 2379, 2519])) {
            return;
        }
        checkedProgress = true;
        log("Progress verified. Resuming saga...");
    }

    // Step-by-step quest blocks:
    if (quest(2239, "thespan")) {
        if (!mapItem(1358, "Tek's Notes", 1)) return;
        if (!mapItem(1359, "Warlic's Notes", 1)) return;
        complete(2239);
    }

    if (quest(2240, "timelibrary")) {
        if (!hunt("Sneak", "AQ Dimension Key", 1)) return;
        if (!hunt("Tog", "DF Dimension Key", 1)) return;
        complete(2240);
    }

    // Boss fight with solo class switch:
    if (quest(2519, "timespace")) {
        equipLoadout("solo");
        if (!hunt("Chaos Lord Iadoa", "Iadoa Defeated", 1)) return;
        complete(2519);
    }
}
```

---

### Pattern 2: Continuous Background Auto-Quest Farm
For repetitive gold, EXP, or reputation farming in a single zone:
```javascript
function onStart() {
    acceptAllDrops();
    equipLoadout("farm");
    join("shadowbattleon");
    autoQuest([9421, 9422, 9423]); // Runs in background
}

function onTick() {
    ensureMap("shadowbattleon");
    ensureCombat();
}

function onStop() {
    stopAutoQuest();
    stopCombat();
    ensureHouse();
}
```

---

## AI Script Generation Guide

When using an AI assistant to generate new `.hxs` scripts, provide these rules:

> **System Prompt for Script Generation:**
> 1. Always implement `function onStart()`, `function onTick()`, and `function onStop()`.
> 2. Use direct top-level methods (`quest`, `mapItem`, `hunt`, `complete`, `ensureMap`, `ensureHouse`, `hasItem`, `stop`, `log`). Do NOT use `bot.` or `map.` prefixes.
> 3. For storyline/saga quests, use the step-by-step pattern:
>    ```haxe
>    if (quest(QUEST_ID, "mapname")) {
>        if (!mapItem(ITEM_ID, "Item Name", QTY)) return;
>        if (!hunt("Monster Name", "Drop Name", QTY)) return;
>        complete(QUEST_ID);
>    }
>    ```
> 4. For multi-quest storylines, add the safe house milestone check on startup:
>    ```haxe
>    if (!checkedProgress) {
>        if (!isHouse()) { ensureHouse(); return; }
>        if (!ensureQuestsLoaded([ID1, ID2, ...])) return;
>        checkedProgress = true;
>    }
>    ```
> 5. If the quest requires items that might be in the bank, call `unbankPreset("name")` in `onStart()`.
> 6. On script completion or `onStop()`, always finish safely with `ensureHouse();`.
> 7. Never loop on `ensureQuest(id)`. It returns `true` for an already-completed quest, and `false` only while a load or accept is still in flight — write `if (!ensureQuest(ID)) return;` once per tick, never `while (!ensureQuest(ID))`.
> 8. Use `log()` for anything a loop may repeat and `notify()` for a one-off message the user must not miss. Do not use `msg()` inside `onTick()` — it writes to both the log and a notification card.
