# AQW Skill Rotation DSL Reference & Guide

This document is the authoritative specification and user guide for the **AQW Skill Rotation DSL** (Domain-Specific Language) implemented in `com.aqwapi.utils.SkillDslParser` and executed by `com.aqwapi.modules.CombatEngine`.

It is written so that humans and AI/LLMs can understand, parse, and generate valid class rotation configs.

---

## 1. Quick Syntax Overview

A rotation is a chain of skill slots executed in order:
```text
1 > 2 > 3 > 4
```

Skills can be gated by conditional rules in square brackets `[...]`:
```text
0[!aura(self:Vehemency)] > 2 > 2
```

Multiple conditional sub-rotations (branches) can be joined using the pipe `|` operator:
```text
0[!aura(self:Vehemency)] > 2 > 2 | 0[!aura(self:Superpower)] > 2 > 3 | 4[aura(self:Vehemency) & aura(self:Superpower)] | 0 > 1 > 1
```

---

## 2. Skill Slots

| Token | Meaning | Notes |
| :--- | :--- | :--- |
| `0` or `aa` | Action Bar Slot 0 | Auto Attack on standard classes; active damage/buff skill on classes like Chrono ShadowHunter or Archivist. |
| `1` | Skill 1 | First active class skill (mapped to "a1"). |
| `2` | Skill 2 | Second active class skill (mapped to "a2"). |
| `3` | Skill 3 | Third active class skill (mapped to "a3"). |
| `4` | Skill 4 | Fourth active class skill (mapped to "a4"). |
| `5` | Skill 5 | Fifth slot (potions/scrolls/extra skill, mapped to "a5"). |

---

## 3. Condition Rules Reference

Conditions are placed inside square brackets `[ ... ]` immediately following a skill slot.

### 3.1. Auras (Buffs & Debuffs)

| Rule Syntax | Target | Description | Example |
| :--- | :--- | :--- | :--- |
| `aura(self:Name)` | Player | True if aura is active on player (stacks > 0). | `4[aura(self:Focus)]` |
| `!aura(self:Name)` | Player | True if aura is NOT active on player (stacks == 0). | `2[!aura(self:Vehemency)]` |
| `aura(target:Name)` | Target | True if aura is active on target. | `1[aura(target:Decay)]` |
| `!aura(target:Name)` | Target | True if aura is NOT active on target. | `0[!aura(target:Splotched)]` |
| `aura(self:Name) >= N` | Player | True if aura has at least `N` stacks. | `4[aura(self:Chaos) >= 3]` |
| `aura(self:Name) <= N` | Player | True if aura has at most `N` stacks. | `1[aura(self:Rounds Empty) <= 1]` |
| `aura(Name)` | Player | Omitting target defaults to `self`. | `3[aura(Temporal Rift)]` |

> **Note on Aura Names**: Multi-word aura names with spaces are fully supported (e.g., `self:Page Turned`, `self:Temporal Rift`). Case-insensitive comparison is used.

### 3.2. Aura Expiration / Remaining Time

Checks remaining duration before an aura expires:

| Rule Syntax | Description | Example |
| :--- | :--- | :--- |
| `auraTime(self:Name) <= 1.5s` | Aura duration remaining on player is $\le 1.5$ seconds. | `2[auraTime(self:Focus) <= 1.5s]` |
| `auraRemaining(target:Name) < 2s` | Aura duration remaining on target is $< 2$ seconds. | `3[auraRemaining(target:DoT) < 2s]` |

Aliases: `auraTime(...)`, `aura_time(...)`, `auratimer(...)`, `auraremaining(...)`.
Units: Seconds (`s`) or milliseconds (`ms`).

### 3.3. Player Health (HP)

| Rule Syntax | Description | Example |
| :--- | :--- | :--- |
| `hp < 50%` | Current player HP is below 50% of max HP. | `2[hp < 50%]` |
| `hp > 80%` | Current player HP is above 80% of max HP. | `4[hp > 80%]` |
| `hp < 2500` | Flat HP threshold (values > 100 are automatically treated as flat HP). | `2[hp < 2500]` |

Aliases: `hp`, `health`. Comparisons: `<`, `<=`, `>`, `>=`, `==`.

### 3.4. Player Mana (MP)

| Rule Syntax | Description | Example |
| :--- | :--- | :--- |
| `mp > 30%` | Player MP is above 30% of max MP. | `3[mp > 30%]` |
| `mp < 20%` | Player MP is below 20% of max MP. | `1[mp < 20%]` |
| `mp > 40` | Flat MP threshold. | `4[mp > 40]` |

Aliases: `mp`, `mana`. Comparisons: `<`, `<=`, `>`, `>=`, `==`.

### 3.5. Target Health

| Rule Syntax | Description | Example |
| :--- | :--- | :--- |
| `tgt:hp > 50%` | Target current HP is above 50%. | `0[tgt:hp > 50%]` |
| `tgt:hp < 20%` | Target current HP is below 20%. | `4[tgt:hp < 20%]` |
| `target:hp > 500000` | Flat target HP threshold. | `3[target:hp > 500000]` |

Aliases: `tgt:hp`, `target:hp`, `target_hp`, `target.hp`, `mon:hp`, `tgt:health`, `target:health`.

### 3.6. Party Health

| Rule Syntax | Description | Example |
| :--- | :--- | :--- |
| `party:hp < 50%` | Any party member in the room is below 50% HP. | `3[party:hp < 50%]` |

Aliases: `party:hp`, `party_hp`, `party.hp`, `party:health`.

### 3.7. Counter & Reaction (Incoming Enemy Attacks)

Used for classes with riposte, dodge, or reactionary counters:

| Rule Syntax | Type | Description |
| :--- | :--- | :--- |
| `[counter]` | Hard Lock | Holds the rotation until the enemy resolves an attack against the player. Will not skip or time out. |
| `[counter <= 1.5s]` | Timed Window | Passes if the enemy attacked within the last 1.5 seconds. |
| `[counter=dodge <= 2s]` | Typed Window | Passes if the enemy's attack was dodged within the last 2 seconds. Supported types: `hit`, `crit`, `miss`, `dodge`, `parry`, `block`. |
| `[counter x3]` | Hit Count | Waits until 3 enemy attacks have resolved before passing. |

Aliases: `counter`, `hit`, `attacked`, `mobattack`.

### 3.8. Artificial Delays

| Rule Syntax | Description | Example |
| :--- | :--- | :--- |
| `wait(500ms)` | Waits 500 milliseconds before allowing this skill to fire. | `2[wait(500ms)]` |

### 3.9. Skill Cooldown & Readiness Checks

Allows checking if a skill is ready to fire or currently on cooldown:

| Rule Syntax | Description | Example |
| :--- | :--- | :--- |
| `!cd(X)` / `!cooldown(X)` | Skill `X` is off cooldown (cooldown $\le 0$). | `4[!cd(4)]` or `0[!cd(4)] > 4` |
| `ready(X)` | Skill `X` is off cooldown and ready to fire. | `4[ready(4)]` |
| `!onCooldown(X)` | Skill `X` is not on cooldown. | `4[!onCooldown(4)]` |
| `cd(X)` / `onCooldown(X)` | Skill `X` is currently on cooldown (cooldown $> 0$). | `2[cd(4)]` |
| `!ready(X)` | Skill `X` is NOT ready (on cooldown). | `2[!ready(4)]` |
| `cd(X) <= 1.5s` | Remaining cooldown on skill `X` is $\le 1.5$ seconds. | `4[cd(4) <= 1.5s]` |
| `cd(X) == 0` | Remaining cooldown on skill `X` is exactly 0. | `4[cd(4) == 0]` |

> [!TIP]
> **Omitting the skill index**: When used on a skill without specifying `(X)`, the rule checks the current skill slot itself:
> - `4[!cd]` $\equiv$ `4[!cd(4)]`
> - `4[ready]` $\equiv$ `4[ready(4)]`
> - `4[cd <= 1.5s]` $\equiv$ `4[cd(4) <= 1.5s]`
> - `4[!oncooldown]` $\equiv$ `4[!oncooldown(4)]`

---

## 4. Logical Operators Inside Brackets

You can combine multiple conditions on a single skill using:
- **`&` (AND)**: All conditions must pass.
- **`|` (OR)**: At least one condition must pass.

### Examples:
```text
// Cast skill 4 only if player has both Vehemency and Superpower auras:
4[aura(self:Vehemency) & aura(self:Superpower)]

// Cast skill 0 if target lacks Splotched AND target HP is above 50%:
0[!aura(target:Splotched) & tgt:hp > 50%]

// Cast emergency heal if player HP is under 40% OR party HP is under 50%:
3[hp < 40% | party:hp < 50%]
```

---

## 5. Branching Rotations (`|`)

When a rotation string contains the pipe character `|` between skill chains, it defines multiple **priority branches**:

```text
Branch1 | Branch2 | Branch3 | Fallback
```

### Execution Lifecycle:
1. **Selection (Top-to-Bottom / Left-to-Right)**:
   - Evaluates the **first skill** of each branch in order.
   - For a branch to be chosen:
     - Its first skill's condition rules must pass.
     - Its first skill must be off cooldown (or ready within the configured timeout window).
   - The first branch meeting these criteria is **locked**.
2. **Execution**:
   - The engine steps through all skills in the locked branch until completed.
3. **Reset**:
   - Once all skills in the locked branch have fired, the branch unlocks.
   - On the next tick, branch selection begins again from the very first branch.
4. **Fallback Branch**:
   - Place an unconditional branch at the end (e.g. `| 0 > 1 > 1` or `| 1 > 2`) so the bot always has a default rotation when no conditional branches match.

---

## 6. Rotation Modes & Configuration

Config files (`skills.json`, `userSkills.json`, or `.ini` format) define class modes with these settings:

```ini
[ClassName : ModeName]
mode = WaitForCooldown
timeout = 1500
autoattack = false
resetontarget = true
combo = 0[!aura(self:Vehemency)] > 2 > 2 | 0[!aura(self:Superpower)] > 2 > 3 | 4[aura(self:Vehemency) & aura(self:Superpower)] | 0 > 1 > 1
```

### Key Parameters:

| Key | Values | Default | Description |
| :--- | :--- | :--- | :--- |
| `mode` (or `skillUseMode`) | `WaitForCooldown`, `UseIfAvailable` | `WaitForCooldown` | Controls how the engine behaves when a skill is on cooldown. |
| `timeout` (or `skillTimeout`) | Milliseconds (e.g. `1500`) | `1500` (WFC), `0` (UIA) | Wait time before skipping a blocked skill (see below). |
| `autoattack` (or `auto`) | `true`, `false` | `true` | Controls the native Auto Attack routine. |
| `resetontarget` | `true`, `false` | `false` | If `true`, restarts combo from the beginning when switching targets. |
| `stopOnTargetAuras` | Comma-separated aura names | `""` | Target auras (reflect/counter) that cause combat to pause. |

---

## 7. Deep-Dive: Execution Modes

### 7.1. `WaitForCooldown`
- Steps through skills sequentially: $S_0 \to S_1 \to S_2 \dots$
- If the current skill is on cooldown or waiting for GCD, the engine **waits**.
- Minimum timeout is clamped to **1 GCD ($1500\text{ms}$)**.
- If the skill remains blocked after `timeout` ms, it advances to the next skill.

### 7.2. `UseIfAvailable`
- Scans skills sequentially.
- If a skill's rules fail or it is on cooldown:
  - If `timeout == 0` (default): **Skips immediately** to the next skill.
  - If `timeout > 0`: **Waits up to `timeout` ms** before skipping to the next skill.

### 7.3. `autoattack` Setting (Crucial for Slot 0)
- **`autoattack = true` (Standard classes)**:
  - The game's native Auto Attack routine runs independently in parallel.
  - Native autoattack has no GCD and never locks skills.
  - In skill rotations, any slot `0` is **ignored and skipped with zero delay**.
- **`autoattack = false` (Special classes like Chrono ShadowHunter, Archivist of Time / Temporis)**:
  - Native autoattack routine is cancelled (`clearNativeAutoAttack`).
  - Slot `0` is a **genuine skill with GCD**.
  - Slot `0` is fully evaluated with rules, cooldowns, and GCD gates just like skills 1–5.
  - Branch selection gates on slot `0`'s cooldown readiness.

---

## 8. Complete Working Examples

### Example 1: Archivist of Temporis / Archivist of Time (Spellbook Inscription & Index Combos)

**Class Mechanics:**
- **Slot 0 (`0`)**: *Lorebook of Beginnings* (4.5s CD, Inscribes Lore, **restores 100% mana**, triggers Rank 10 *Epigraph* for 50% Damage Resistance for 8s on pull).
- **Slot 1 (`1`)**: *The First Index* (Damaging spells, costs 40 mana, 1.5s CD).
- **Slot 2 (`2`)**: *The Second Index* (Enchanting spells, costs 40 mana, 1.5s CD).
- **Slot 3 (`3`)**: *The Third Index* (Protection spells, costs 40 mana, 1.5s CD).
- **Slot 4 (`4`)**: *Rewrite Time* (50s CD, refreshes all active Index buff durations on self to full 12s and grants them to allies).

**Index Spell Combinations:**
| Combo | Spells Invoked | Effect / Aura Applied | Duration |
| :--- | :--- | :--- | :--- |
| `0 > 1 > 2` | Lorebook $\to$ 1st Index $\to$ 2nd Index | **Splotched**: Target DoT based on target HP% | 6s |
| `0 > 2 > 2` | Lorebook $\to$ 2nd Index $\to$ 2nd Index | **Vehemency**: +40% Physical & Magical Damage | 12s |
| `0 > 2 > 3` | Lorebook $\to$ 2nd Index $\to$ 3rd Index | **Superpower**: +30% INT, STR, and Luck | 12s |
| `0 > 1 > 3` | Lorebook $\to$ 1st Index $\to$ 3rd Index | **Page Turned**: Successive Lorebook damage scaling | 24s |
| `4` | Rewrite Time | **Buff Refresh**: Resets all active buffs to full 12s | 50s CD |
| `0 > 1 > 1` | Lorebook $\to$ 1st Index $\to$ 1st Index | **Burst Damage**: Direct damaging spell spam | Instant |
| `0 > 3 > 2` | Lorebook $\to$ 3rd Index $\to$ 2nd Index | **Resiliency**: +25% Damage Resistance (Defensive) | 24s |
| `0 > 3 > 1` | Lorebook $\to$ 3rd Index $\to$ 1st Index | **Fortification**: +75% END & -25% mana costs | 24s |
| `0 > 3 > 3` | Lorebook $\to$ 3rd Index $\to$ 3rd Index | **Rewind**: Heal over Time (HoT) | 24s |
| `0 > 2 > 1` | Lorebook $\to$ 2nd Index $\to$ 1st Index | **Acutance**: +50% Crit Chance | 12s |

**Configuration & Optimal Rotations:**
> [!IMPORTANT]
> Because slot 0 is *Lorebook of Beginnings* (an active skill with GCD), set `autoattack = false` (or UI `AA: OFF`).
> Splotched (6s duration) must be placed at the very front to prevent priority starvation from 12s buffs.

#### Option A: Zero-Stall Solo Rotation (Pure 4.5s Hand-Off Chains)
Completely eliminates the 50s cooldown skill for a 100% predictable, repeating cycle of 4.5s chains:
```ini
[Archivist of Temporis : Solo-Linear]
mode = WaitForCooldown
timeout = 1500
autoattack = false
resetontarget = true
combo = 0[!aura(target:Splotched) & tgt:hp > 50%] > 1 > 2 | 0[!aura(self:Vehemency)] > 2 > 2 | 0[!aura(self:Superpower)] > 2 > 3 | 0[!aura(self:Page Turned)] > 1 > 3 | 0 > 1 > 1
```

#### Option B: Advanced Solo / Group Rotation (Infinite Page Turned & Clean Rewrite Time)
Maintains *Page Turned* indefinitely on the enemy without losing stacks, refreshes *Vehemency* and *Superpower* via Skill 4 (*Rewrite Time*) every 50 seconds, and seamlessly transitions into direct burst damage:
```ini
[Archivist of Temporis : Solo-Optimal]
mode = WaitForCooldown
timeout = 1500
autoattack = false
resetontarget = true
combo = 0[!aura(target:Page Turned) | auraTime(target:Page Turned) <= 5s] > 1 > 3 | 4[ready(4) & aura(self:Vehemency)] | 0[!aura(self:Vehemency)] > 2 > 2 | 0[!aura(self:Superpower)] > 2 > 3 | 0[!aura(target:Splotched) & tgt:hp > 50%] > 1 > 2 | 0 > 1 > 1
```

**Why This Resolves Both Issues:**
1. **Infinite Page Turned Stacking (`target:Page Turned`)**:
   - *Page Turned* is an enemy debuff (`target`), not a player buff (`self`).
   - Using `!aura(target:Page Turned) | auraTime(target:Page Turned) <= 5s` ensures it casts at combat start when missing, **AND** re-casts `0 > 1 > 3` whenever the 24s timer drops below 5s.
   - The 24-second timer is refreshed back to full **before it expires**, preserving all accumulated stacks indefinitely!
2. **Rewrite Time Recasting (`ready(4) & aura(self:Vehemency)`)**:
   - Placing `4[ready(4) & aura(self:Vehemency)]` ahead of the manual buff branches guarantees that whenever Skill 4 comes off its 50s cooldown and buffs are active, it fires immediately:
     - Refreshes both *Vehemency* and *Superpower* back to 12s in a single 1.5s GCD.
     - Does **not** append `> 1 > 1` to Skill 4: Index skills cost 40 MP each, and because the previous combo left the player at 20 MP, trying to cast `1` without `0` causes mana starvation and a 3-second timeout stall.
     - Instead, Skill 4 finishes cleanly in 1.5s. By then, Slot 0's 4.5s cooldown has already expired in the background (6.0s elapsed since last cast). The bot immediately enters `0 > 1 > 1`, where Slot 0 instantly refills mana to 100 with **zero idle pause**!
   - For the next 50 seconds while Skill 4 recharges, the engine's fixed native cooldown tracker cleanly skips Branch 1 with 0ms delay, and the bot naturally falls back to manual upkeep (`0 > 2 > 2` and `0 > 2 > 3`) whenever buffs expire.
3. **Burst DPS**: When buffs, DoT, and Page Turned are active, the bot continuously spams `0 > 1 > 1` to deal astronomical damage with high Page Turned stacks!

#### Option C: Linear Full-Buff Ramp & Burst Sequence (34-Step Cycle)
A deterministic, non-branching sequence that applies all core buffs, triggers Skill 4 (*Rewrite Time*), immediately restores mana with `0`, and unloads three full burst cycles before looping:
```ini
[Archivist of Temporis : Linear-Ramp]
mode = WaitForCooldown
timeout = 1500
autoattack = false
resetontarget = true
combo = 0 > 1 > 3 > 0 > 3 > 1 > 0 > 3 > 2 > 0 > 3 > 3 > 0 > 2 > 1 > 0 > 2 > 2 > 0 > 2 > 3 > 4 > 0 > 1 > 1 > 0 > 1 > 1 > 0 > 1 > 1 > 0 > 1 > 3
```

**Why the `> 4 > 0 > 1 > 1` Transition Works Flawlessly:**
* **Buff Refresh**: Skill 4 (*Rewrite Time*, 1.5s) refreshes all active 12-second buffs back to maximum duration.
* **Instant Mana Restoration**: By placing `0` (*Lorebook of Beginnings*) directly after `4`, the player instantly recovers 100 MP with **0ms delay** (because Slot 0 had 6.0 seconds to recharge since the previous combo).
* **Burst Nukes**: With full 100 MP, the three successive `0 > 1 > 1` burst cycles fire without any resource stalling or cooldown desync!
* **Target Behavior**: For bosses / high-HP targets, use `resetontarget = true`. When farming fast-dying trash mobs, toggle `resetontarget = false` so target deaths don't reset to Slot 0 mid-recharge.

### Example 2: Chrono ShadowHunter (Riposte & Dodge Counter)
Slot 0 is a skill, slot 3 is a riposte that requires a mob hit.
```ini
[Chrono ShadowHunter : Dodge]
mode = WaitForCooldown
timeout = 1500
autoattack = false
resetontarget = true
combo = 1 > 2 > 3[counter] > 2 > 3[counter] > 2 > 3[counter] > 4
```

### Example 3: Void Highlord (Health Thresholds & Stacks)
```ini
[Void Highlord : Solo]
mode = WaitForCooldown
timeout = 1500
autoattack = true
resetontarget = true
combo = 2[hp > 60%] > 4[hp > 40%] > 1 > 3 > 5
```

### Example 4: Legion Revenant (Priority Buff Rotation)
```ini
[Legion Revenant : Farm]
mode = UseIfAvailable
timeout = 0
autoattack = true
resetontarget = false
combo = 4[!aura(self:Depravity)] > 3[!aura(self:Anathema)] > 1 > 2
```

---

## 9. Guidelines for AI / LLM Generation

When an AI assistant is asked to create or update an AQW rotation:

1. **Check Slot 0**:
   - Does this class have Auto Attack on slot 0? $\to$ Set `autoattack = true`. Do not use `0` as a conditional trigger.
   - Does this class have an active skill on slot 0 (Archivist, Chrono ShadowHunter)? $\to$ Set `autoattack = false`.
2. **Branching Order**:
   - Order branches by **priority**: Buff upkeep first, nuke second, fallback rotation last.
   - The final branch should have no conditions so the bot never deadlocks.
3. **Use Accurate Aura Names**:
   - Specify the target explicitly: `self:AuraName` or `target:AuraName`.
   - Preserve exact aura name casing and spacing (e.g. `self:Temporal Rift`).
4. **Choose the Right Mode**:
   - Strict sequences (combos that must execute in order) $\to$ `WaitForCooldown` (`timeout = 1500`).
   - Priority spam rotations (fire whatever is off cooldown) $\to$ `UseIfAvailable` (`timeout = 0`).
