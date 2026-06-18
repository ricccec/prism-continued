# Chapter 9 — The Battle Engine

*Every encounter is a small virtual machine that boots, runs its turn loop, and shuts down — and the ROM holds the bytecode for roughly two hundred distinct moves.*

---

The battle engine is the largest single subsystem in Pokémon Prism. It spans four ROMX sections, roughly two dozen subdirectories, and somewhere north of ten thousand lines of assembly. What follows is a guided tour at the altitude of a design document: enough to let you navigate any corner of that tree and understand what you are looking at, without cataloguing every move.

---

## Entering a Battle

When the overworld decides a battle should happen — a random encounter triggers, a trainer walks into the player's line of sight, or a script fires a battle event — control eventually arrives at `StartBattle` in `battle/engine/core/controller.asm`. The function does three things in sequence:

```asm
; battle/engine/core/controller.asm
StartBattle:
    call CancelMapSign
    call BattleIntro
    call DoBattle
    ; ... cleanup
    call ExitBattle
```

`BattleIntro` is the flashy screen wipe you see before the battle HUD appears. Its entry point is `Predef_StartBattle` in `engine/battle_start.asm`, reached via `predef` from ROM0 so it can be called from any bank (see Chapter 2 for the `predef`/`farcall` machinery). That file owns the entire transition animation system: five distinct wipe styles — cave flash, zoom-to-black, spin-to-black, random scatter, and the gym-leader VS portrait sequence — all driven by a `jumptable FlashyTransitionJumptable` state machine. Which animation fires depends on context: `StartTrainerBattle_DetermineWhichAnimation` checks `wOtherTrainerClass` (gym leader or not), `wPermission` (cave or open-air map), and the relative level of the lead Pokémon.

Before the wipe begins, `DoBattleStartFunctions` in `battle/initialize.asm` prepares the battle state:

```asm
; battle/initialize.asm
DoBattleStartFunctions:
    call PlayBattleMusic
    call ShowLinkBattleParticipants
    call FindFirstAliveMon
    ; fallthrough to ClearBattleRAM
ClearBattleRAM:
    xor a
    ld [wBattlePlayerAction], a
    ld [wBattleResult], a
    ; ... zero wBattle through wBattleEnd
    callba ResetEnemyStatLevels
```

`FindFirstAliveMon` walks `wPartyMon1HP` to find the first non-fainted Pokémon and records its level in `wBattleMonLevel`, which `StartTrainerBattle_DetermineWhichAnimation` reads moments later. For wild battles `wBattleMode` is set to 1 (`WILD`); for trainer battles it is 2 (`TRAINER`). That flag threads through the entire engine and drives dozens of branch decisions — stat-experience logic, flee checks, AI activation, and prize-money calculation all test it.

---

## Subsystem Map

Before diving into individual mechanics, it helps to know which directory handles what. The master include file is `battle/files.asm`; everything the linker needs appears there in section order.

| Path | Concern |
|---|---|
| `battle/engine/core/` | `StartBattle`, `DoBattle`, `BattleTurn`, `DoPlayerTurn`, `DoEnemyTurn` |
| `battle/engine/actions/` | Battle menu, move-selection screen, switch handler, flee attempt |
| `battle/engine/abilities/` | Entrance abilities (e.g. Intimidate), end-turn abilities, switch-blocking |
| `battle/engine/endturn/` | Residual damage, weather, screens, Leftovers, Encore, Perish Song |
| `battle/engine/experience/` | EXP and stat-EV award, EXP bar animation, Exp Share |
| `battle/engine/finish/` | Win text, prize money, losing, `ExitBattle` |
| `battle/engine/link/` | Link-battle randomness and result recording |
| `battle/engine/util/` | Speed comparison, HP fraction helpers, stat modifiers, turn-order calc |
| `battle/effects/` | Effect command interpreter, per-command implementations, damage calc |
| `battle/moves/` | Move data table, effect-ID → function pointer table, effect scripts |
| `battle/ai/` | Move scoring, switch scoring, item usage |
| `battle/anim_commands.asm` | Animation script interpreter |
| `battle/anims.asm` | Per-move animation script table |
| `battle/anim_objects.asm` | Sprite object management for in-battle effects |
| `battle/type_matchup.asm` | Full 28×28 effectiveness table |
| `battle/abilities.asm` | Ability lookup and trainer-mon ability derivation |
| `battle/badge_boosts.asm` | Badge-count stat bonuses |

Code that needs to be callable from any bank (helper functions that the scripting VM or overworld engine also use) lives in `home/battle.asm`, which stays in ROM0. That file provides primitives like `BattlePartyAttr` (read an attribute from the active player mon's party struct), `OTPartyAttr` (same for the enemy), and `ResetDamage` (zero the damage scratchpad at the top of each turn).

---

## The Turn Loop

`DoBattle` in `battle/engine/core/main_loop.asm` is the main loop. It runs until `wBattleEnded` becomes non-zero:

```asm
; battle/engine/core/main_loop.asm (abridged)
DoBattle:
    ; ... send out first Pokémon, apply Spikes, etc.
.do_turn
    call AbilityOnMonEntrance
    callba AIChooseMove         ; trainer AI picks a move
    call CheckPlayerLockedIn
.battle_menu_loop
    call BattleMenu             ; player picks action
    call ParsePlayerAction
    call DetermineMoveOrder     ; who goes first?
    call BattleTurn             ; execute both moves
    call HandleEndTurnEffects   ; burn/poison/weather/etc.
    jr z, .do_turn
```

### Action Selection

The player's path through `BattleMenu` (in `battle/engine/actions/battle_menu.asm`) opens the familiar Fight/Bag/Pokémon/Run menu, then delegates to `MoveSelectionScreen` (`battle/engine/actions/move_selection_menu.asm`) which reads PP from `wBattleMonPP`, greys out zero-PP slots, and stores the chosen move index in `wCurPlayerMove`. If the Pokémon is locked into a move (Rage, Encore, two-turn moves), `CheckPlayerLockedIn` short-circuits the menu entirely and the stored move is replayed.

The AI's path runs before the menu appears. `AIChooseMove` in `battle/ai/move.asm` initialises all four move scores to 20 (lower is better), marks disabled and zero-PP moves with score 80, then walks a list of AI scoring layers whose identity depends on `wTrainerClass`:

```asm
; battle/ai/move.asm
.ApplyLayers
    ld hl, TrainerClassAttributes + TRNATTR_AI_MOVE_WEIGHTS
    ld a, [wTrainerClass]
    dec a
    ld bc, 7   ; per-class stride
    rst AddNTimes
```

Each scoring layer is a separate routine: `AI_Basic` penalises redundant status moves (do not try to paralyse an already-paralysed target); `AI_Setup` strongly encourages stat-up moves on the enemy mon's first turn, and discourages them in later turns; further layers handle type-based encouragement, ability-aware checks, and pinch behaviour. After all layers run, the move with the lowest accumulated score is selected.

### Speed and Turn Order

`DetermineMoveOrder` in `battle/engine/util/turn_order.asm` resolves who moves first. It first checks move priority (Quick Attack, Protect, etc.) via `CompareMovePriority`. Equal-priority ties go to `CheckSpeedWithQuickClaw`, which compares `wBattleMonSpeed` against `wEnemyMonSpeed` — with a small Quick Claw random-trigger check — and returns `carry` set if the player goes first. The result feeds directly into `BattleTurn`:

```asm
; battle/engine/core/main_loop.asm
BattleTurn:
    jr c, .player_first
    ; enemy goes first: do enemy turn, check faint, then do player turn
.player_first:
    ; player goes first: do player turn, check faint, then do enemy turn
```

After both sides have moved, `HandleEndTurnEffects` in `battle/engine/endturn/main.asm` ticks through residual effects in a fixed priority order: faint checks, burn/poison/Leech Seed damage, Future Sight landing, weather damage, Wrap damage, Perish Song countdown, Leftovers healing, Safeguard countdown, screen countdown, healing berries, end-turn abilities.

---

## Move Execution

### Effect Scripts

Every move entry in `battle/moves/moves.asm` carries seven fields packed by the `move` macro:

```asm
; battle/moves/moves.asm
MACRO move
    db \1  ; animation ID
    db \2  ; effect ID
    db \3  ; power
    db \4 | (\5 << 6)  ; type | category
    db \6  ; accuracy
    db \7  ; pp
    db \8  ; effect chance
ENDM

    move POUND, EFFECT_NORMAL_HIT, 40, NORMAL, PHYSICAL, 100, 35, 0
    move FIRE_PUNCH, EFFECT_BURN_HIT, 75, FIRE, PHYSICAL, 100, 15, 10
```

The `effect ID` indexes into `MoveEffectsPointers` in `battle/moves/move_effects_pointers.asm`, a flat table of `dw` entries:

```asm
; battle/moves/move_effects_pointers.asm
MoveEffectsPointers:
    dw NormalHit    ; 00
    dw DoSleep      ; 01
    dw PoisonHit    ; 02
    dw LeechHit     ; 03
    dw BurnHit      ; 04
    ; ...
```

Each label points into `battle/moves/move_effects.asm`, which holds terse scripts written in a domain-specific assembly language built on top of real GB opcodes. Each script is a sequence of one-byte effect command tokens terminated by `endmove`:

```asm
; battle/moves/move_effects.asm
NormalHit:
    checkobedience
    usedmovetext
    doturn
    pressure
    critical
    damagestats
    damagecalc
    typematchup
    damagevariation
    checkhit
    hittarget
    failuretext
    checkfaint
    criticaltext
    supereffectivetext
    strikeback
    buildopponentrage
    defrostfoe
    kingsrock
    endmove
```

These are not macros emitting inline code — they are single-byte constants enumerated in `battle/effects/effect_commands.asm`. `DoMove` in `battle/effects/execute_turn.asm` copies the entire token sequence into a WRAM buffer (`wBattleScriptBuffer`), then dispatches each byte through `BattleCommandPointers`:

```asm
; battle/effects/execute_turn.asm (abridged)
DoMove:
    ; index MoveEffectsPointers by effect ID → address of effect script
    ld hl, MoveEffectsPointers
    ; copy script bytes to wBattleScriptBuffer
.GetMoveEffect
    call GetFarByteAndIncrement
    ld [de], a
    inc de
    cp $ff
    jr nz, .GetMoveEffect
.ReadMoveEffectCommand
    ; fetch next byte from buffer, dispatch via BattleCommandPointers
    ld hl, BattleCommandPointers
    add hl, bc
    add hl, bc
    add hl, bc  ; each pointer is 3 bytes: dba bank + address
```

The `dba` entries in `BattleCommandPointers` (`battle/effects/effect_command_pointers.asm`) each hold a bank byte plus a two-byte address, letting the dispatcher do a far call to the right handler regardless of which ROMX bank the command lives in. This is the same `farcall` pattern described in Chapter 2, applied to a scripted bytecode engine rather than hand-written call sites.

---

## Damage Calculation and Type Matchup

The damage calculation path, assembled by the command sequence `damagestats → damagecalc → typematchup → damagevariation`, lives under `battle/effects/damage/`. `BattleCommand_DamageStats` (`damage/calculate_stats.asm`) loads the attacker's Attack (or Sp.Atk) and the defender's Defense (or Sp.Def) — already modified by stat-level multipliers — into the calculation scratchpad. `BattleCommand_DamageVariation` (`effect_commands.asm`) then rolls a random number in 0–15 and stores it as a damage variance complemented from 100%:

```asm
; battle/effects/effect_commands.asm
BattleCommand_DamageVariation:
    call BattleRandom
    and 15
    ld [wCurDamageRandomVariance], a  ; 0 = 100%, 15 = 85%
```

Type effectiveness comes from a 28×28 lookup table in `battle/type_matchup.asm`. Prism has 28 types, including several custom additions: Fairy, Gas, Sound, Tri, and Prism itself. Each row is the attacker's type; each column is the defender's type:

```asm
; battle/type_matchup.asm (column headers: NRM FGT FLY PSN GND RCK BRD BUG GST STL FRY GAS ... FIR WTR GRA ELC PSY ICE DRG DRK)
; Fighting (FGT)
    type_matchup SE_, NTL, NVE, NVE, NTL, SE_, NTL, NVE, IMM, SE_, NVE, NVE, NTL, SE_, SE_, NTL, ...
; Dragon (DRG)
    type_matchup NTL, NTL, NTL, NTL, NTL, NTL, NTL, NTL, NTL, NVE, IMM, NTL, ...
```

`SE_` = super effective (×2), `NVE` = not very effective (×0.5), `IMM` = immune (×0), `NTL` = neutral. The lookup is straightforward: the command fetches the attacker's type, multiplies by 28 (the row stride), adds the defender's type, and reads one byte to get the effectiveness constant.

### Badge Boosts

In non-link, non-Battle-Tower battles, `BadgeStatBoosts` in `battle/badge_boosts.asm` raises the player's battle stats before they enter the damage formula. Each badge earned across Naljo, Rijon, and the "Other" group contributes +1/32 to a stat, additively:

```asm
; battle/badge_boosts.asm
    ld a, [wNaljoBadges]
    call .count_from_zero
    ld a, [wRijonBadges]
    call .count_from_three
    ld a, [wOtherBadges]
    and $f
    call .count_from_one
    ; each badge counter scales Attack, Defense, Speed, Sp.Atk, Sp.Def
```

### Abilities

`battle/abilities.asm` handles the ability lookup at battle start. `CalcMonAbility` takes the species from `wCurSpecies` and a pointer to the mon's DVs, calls `GetMonAbilities` (which reads from `BaseData` at offset `wBaseAbilities`), then chooses between the two possible abilities using the parity of the DV bits:

```asm
; battle/abilities.asm
CalcMonAbility::
    call GetMonAbilities
    ld b, 2
    call CountSetBits
    rra             ; carry = parity
    ld hl, wBaseAbilities
    jr nc, .load
    inc hl          ; odd parity → second ability
.load
    ld a, [hl]
```

Trainer-owned Pokémon use `CalcTrainerMonAbility`, which passes species, trainer class, level, trainer ID, party slot, and the first move through `StableRandom` five times to produce a deterministic but varied ability — the same trainer's Pokémon always have the same ability across soft-resets without storing that data in the save file.

Ability *effects* at battle time are dispatched through `battle/engine/abilities/entrance.asm` (triggers on switch-in, e.g. Intimidate lowering the opponent's Attack), `battle/engine/abilities/end_turn.asm` (triggers at end of turn, e.g. speed-boosting abilities), and `battle/engine/abilities/switch_blocking.asm` (e.g. Shadow Tag). Type-modifying abilities that interact with damage (e.g. Levitate for Ground immunity, Flash Fire boosting Fire moves) live in `battle/effects/ability/type_modifiers.asm` and are called during the `typematchup` command.

---

## Battle Animations

Each move entry carries an animation ID (the first byte in the `move` macro). `battle/anims.asm` is a flat `dw` table indexed by that ID:

```asm
; battle/anims.asm
BattleAnimations::
    dw BattleAnim_NoAnimation
    dw BattleAnim_Pound
    dw BattleAnim_KarateChop
    dw BattleAnim_Doubleslap
    ; ...
    dw BattleAnim_PrismSpray
```

When a move executes, `PlayBattleAnim` in `battle/anim_commands.asm` takes over display control, switches the VBlank handler to mode 3, and calls `BattleAnimRunScript`:

```asm
; battle/anim_commands.asm
PlayBattleAnim:
    ; enable LCD_STAT interrupt
    ; assign and load palettes
    ld [hl], 3         ; hVBlank = mode 3
    call BattleAnimRunScript
    ; restore palettes, wait for SFX, restore hVBlank
```

`RunBattleAnimScript` drives the per-frame loop: it calls `RunBattleAnimCommand` to consume one command from the animation script, then runs `ExecuteBGEffects`, updates OAM, requests palette updates, and waits a frame. The loop repeats until the animation script sets `wBattleAnimFlags` bit 0. Sprite objects spawned by animations (projectile tiles, flash effects) are managed by `battle/anim_objects.asm`, which keeps a pool of active objects in WRAM and moves them each frame according to velocity and decay rules.

The miss-hit sound variant is also handled here: if `wNumHits` is non-zero when the main animation finishes, `BattleAnimRunScript` replays a sub-animation (`ANIM_MISS + wNumHits`) to show the multi-hit count indicator.

---

## Trainer AI

The AI subsystem lives under `battle/ai/` with three primary files.

`battle/ai/move.asm` scores moves as described above. The default score of 20 means "neutral preference"; the chosen move is whichever slot has the lowest final score after all layers apply. `AIDiscourageMove` adds a penalty; `AIEncourageMove` subtracts one. Disabled and no-PP moves score 80 — never chosen unless all four are penalised, in which case the engine falls back to Struggle.

`battle/ai/scoring.asm` contains the individual scoring layer routines. `AI_Basic` discourages obviously wasteful moves (trying to sleep an already-sleeping target). `AI_Setup` biases toward setup moves on turn one:

```asm
; battle/ai/scoring.asm
AI_Setup:
; 50% chance to greatly encourage stat-up moves during the first turn of the enemy's Pokémon.
; 50% chance to greatly encourage stat-down moves during the first turn of the player's Pokémon.
; ~90% chance to greatly discourage stat-modifying moves otherwise.
```

`battle/ai/switch.asm` handles the switch decision. `GetSwitchScores` iterates the enemy party, skips fainted members, calls `CalcPartyMonAbility` and `AICheckMatchupForEnemyMon` for each candidate, and records the highest type-matchup score as the preferred switch target. The active mon's score is compared against the best bench score; if the bench is significantly better, `AI_SwitchOrTryItem` in `battle/engine/core/main_loop.asm` triggers the switch.

Trainer class identity (read from `wTrainerClass`) controls which layers are active via the `TRNATTR_AI_MOVE_WEIGHTS` field in `TrainerClassAttributes`. A basic Youngster might use only `AI_Basic`; a Gym Leader stacks several layers including type-awareness and pinch behaviour. Trainer class data and party definitions come from the trainer data structures described in Chapter 4 (base species data) and Chapter 7 (trainer NPC events that initiate the battle).

---

## Catching Pokémon

Wild battles open a slightly different path: the Bag menu is available, and a ball throw drives the catch attempt. The catch logic (`battle/misc.asm` and related) checks the wild Pokémon's current HP fraction, status condition, ball type, and a PRNG roll against the catch rate from the species' base data. Four shake animations follow; if all four pass, the ball locks.

---

## Battle End: EXP, EVs, and Prize Money

When the enemy's final Pokémon faints, `HandleEnemyMonFaint` sets `wBattleEnded` and calls into `battle/engine/finish/won.asm` → `WinTrainerBattle`. After playing victory music and displaying the defeat text, `GiveExperiencePoints` in `battle/engine/experience/award_exp_points.asm` iterates the player's party:

```asm
; battle/engine/experience/award_exp_points.asm
GiveExperiencePoints:
    ; for each party member that participated or has Exp Share:
    call GiveStatExperience    ; EV gain
    ; base exp = wEnemyMonBaseExp * wEnemyMonLevel / 7
    ; (or /21 if Hyper Share engine flag is set — all mons share equally)
    ; boost for traded mons, Lucky Egg, etc.
```

The base EXP formula matches Gen 2: `(base_exp × enemy_level) / 7`, divided by the number of participants if multiple Pokémon battled (unless the Hyper Share engine flag is active). Stat EXPs (EVs) from `GiveStatExperience` read the defeated species' stat-experience yields from base data.

Prize money follows. `WinTrainerBattle` calls `.give_money`, which reads `wBattleReward` (computed from trainer class and level at battle init), applies the Amulet Coin doubling, and distributes the reward between `wMoney` (wallet) and `wBankMoney` depending on the player's bank-saving setting (`wBankSavingMoney`). A fraction of winnings can be auto-banked at rates of ¼, ½, or the full amount.

After all rewards are distributed, `ExitBattle` in `battle/engine/finish/exit.asm` zeroes all battle-specific WRAM fields, calls `BattleEnd_HandleRoamMons` (to respawn or relocate any roaming Pokémon that may have been encountered), and returns carry-set to the overworld so the caller knows the battle ended.

---

## Where to Next

The battle engine relies on two support layers that fill in the background: the text boxes and menus the engine surfaces to the player (move-selection screens, HP bars, HUD slides), the sound effects triggered by each animation command, and the graphical tile system that displays Pokémon sprites in battle. Chapter 10 covers text rendering, menu architecture, the audio driver, and the graphics pipeline that ties all of it together.
