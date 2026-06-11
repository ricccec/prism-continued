# Chapter 4 — Game Data

*The ROM is mostly data. The code is mostly infrastructure for looking it up.*

---

## 4.1 The Philosophy: Declarative Tables

One of the clearest things you notice when reading the Pokémon Prism source is how little procedural code there is for defining content. Species are not constructed at runtime from scattered fields; they are declared as compact, fixed-size records assembled by a macro. The same pattern repeats for moves, trainers, and items. The assembler computes the binary layout; the programmer writes something that reads almost like a config file.

This is the "data-as-tables" philosophy described in [Chapter 2](02-architecture.md): fixed-size records where possible, pointer tables for variable-length data, and a single canonical constant for every game ID. This chapter walks through the six major content tables in the order you are most likely to encounter them.

---

## 4.2 Pokémon Base Stats

### The record format

Every species has exactly one file under `data/base_stats/`. The files are aggregated by `data/base_stats.asm`, which is one long list of `INCLUDE` directives. Each individual file contains a straight sequence of `db` and `dn` directives — no macro wrapper. Compare `data/base_stats/bulbasaur.asm` and `data/base_stats/pikachu.asm` to see the pattern:

```asm
; data/base_stats/bulbasaur.asm
    db BULBASAUR
    db 45, 49, 49, 45, 65, 65  ; HP, Atk, Def, Spe, SpA, SpD
    db GRASS, POISON
    db 45                       ; catch rate
    db 64                       ; base EXP yield
    db NO_ITEM                  ; common held item
    db MIRACLE_SEED             ; rare held item
    db 31                       ; gender ratio
    db 100                      ; unknown / egg multiplier
    db 20                       ; egg cycles
    db 5                        ; unknown (padding)
    INCLUDE "gfx/pics/bulbasaur/dimensions.asm"
    db ABILITY_OVERGROW, ABILITY_OVERGROW
    db 0, 0                     ; padding
    db MEDIUM_SLOW              ; EXP growth rate
    dn MONSTER, PLANT           ; egg groups (two nibbles via dn)
```

The six base stats are packed in the order HP / Atk / Def / **Spe** / SpA / SpD — speed is third, before the special stats. This matches the internal Crystal ordering and is worth noting because documentation for the vanilla game sometimes lists them in a different order.

### Field-by-field layout

| Offset | Size | Field | Notes |
|--------|------|-------|-------|
| 0 | 1 | Species constant | Self-referential ID |
| 1 | 1 | HP | |
| 2 | 1 | Attack | |
| 3 | 1 | Defense | |
| 4 | 1 | Speed | |
| 5 | 1 | Special Attack | |
| 6 | 1 | Special Defense | |
| 7 | 1 | Type 1 | |
| 8 | 1 | Type 2 | Same as type 1 for mono-type species |
| 9 | 1 | Catch rate | Higher = easier to catch |
| 10 | 1 | Base EXP yield | |
| 11 | 1 | Common held item | 255/256 probability in the wild |
| 12 | 1 | Rare held item | 1/256 probability; `NO_ITEM` if none |
| 13 | 1 | Gender ratio | `0`=always ♂, `254`=always ♀, `255`=genderless, `127`=50/50 |
| 14 | 1 | Unknown | Related to egg hatching |
| 15 | 1 | Egg cycles | Hatch steps = value × 256 |
| 16 | 1 | Unknown | Padding |
| 17–18 | 2 | Sprite dimensions | Pulled from `gfx/pics/<name>/dimensions.asm` |
| 19 | 1 | Ability 1 | `ABILITY_*` constant |
| 20 | 1 | Ability 2 | `ABILITY_NONE` if only one ability |
| 21–22 | 2 | Padding | Two zero bytes |
| 23 | 1 | EXP growth rate | `MEDIUM_FAST`, `MEDIUM_SLOW`, `FAST`, `SLOW`, `ERRATIC`, `FLUCTUATING` |
| 24 | 1 | Egg groups | Two 4-bit nibbles packed via `dn` |

Because the record is fixed-size, the engine can index directly into the table using `rst AddNTimes` — multiply species index by record size, add to base address, done. There is no pointer indirection step for base stats.

### TM/HM learnsets

TM and HM compatibility is stored separately from the base stats record, in `data/tmhmlearnsets.asm`. There is one entry per species, in species-ID order. Each entry is produced by the `tmhm` macro defined in `macros/basestats.asm`:

```asm
; macros/basestats.asm (the tmhm macro, simplified)
MACRO tmhm
    ; ... iterates all arguments, sets bits in five accumulators x/y/w/v/u
    ; then emits 3+3+3+3+1 = 13 bytes (one bit per TM/HM/tutor slot,
    ;   packed across 104 bits = 13 bytes)
    rept 3
    db x & $ff
    x = x >> 8
    endr
    ; ... repeat for y, w, v, then one byte for u
ENDM
```

The call site reads like a move list:

```asm
; data/tmhmlearnsets.asm (Bulbasaur's entry, abbreviated)
    tmhm ANCIENTPOWER, ATTRACT, BODY_SLAM, CURSE, CUT, DEFENSE_CURL, ...
```

Each named argument must have a corresponding `_TMNUM` constant defined by `add_tm`, `add_hm`, or `add_mt` in `data/tmmoves.asm`. The macro checks that constant and sets the corresponding bit in the 104-bit field. If you pass a move name that has no `_TMNUM`, the assembler fails with an explicit error: `\1 is not a TM, HM, or move tutor move`.

The 13-byte result is a bitfield: bit N of the field corresponds to slot N of the TM/HM/tutor list. The ordered list of which move occupies which slot lives in `data/tmmoves.asm`, as a flat array of `db MOVE_NAME` entries ending with `db 0`. At the time of writing there are 100 entries covering TM01–TM50, HM01–HM07, and a set of move tutor moves specific to Prism.

---

## 4.3 Evolutions, Level-Up Movesets, and Egg Moves

### The combined evolutions/moveset record

Level-up learnsets and evolution data share a single pointer table. `data/evos_attacks_pointers.asm` exports `EvosAttacksPointers::`, a flat array of `dw` pointers indexed by species ID:

```asm
; data/evos_attacks_pointers.asm
EvosAttacksPointers::
    dw BulbasaurEvosAttacks
    dw IvysaurEvosAttacks
    dw VenusaurEvosAttacks
    ; ... one pointer per species
```

The pointed-to data lives in `data/movesets/<Name>.asm`, assembled together under the `EvosAttacks::` label in `data/evos_attacks.asm`. Each file has a fixed two-section layout: evolutions first, then level-up moves, then terminators.

```asm
; data/movesets/Bulbasaur.asm
BulbasaurEvosAttacks:
    db EVOLVE_LEVEL, 16, IVYSAUR   ; evolution method, argument, target
    db 0                            ; no more evolutions

    db 1, TACKLE        ; level 1 (starting move)
    db 4, GROWL
    db 7, LEECH_SEED
    ; ...
    db 0                ; no more level-up moves
```

The evolutions section is a sequence of variable-length records, one per evolution path. Each record begins with an `EVO_*` method constant that determines how many argument bytes follow:

| Method | Arguments | Meaning |
|--------|-----------|---------|
| `EVOLVE_LEVEL` | level, species | Evolve at level |
| `EVOLVE_ITEM` | item, species | Use item |
| `EVOLVE_TRADE` | species | Trade |
| `EVOLVE_HAPPINESS` | species | High friendship |
| `EVOLVE_STAT` | stat_cmp, level, species | Level up with stat condition (for Tyrogue) |

`db 0` terminates the evolution list. Immediately after it, the moveset section begins: a sequence of `db LEVEL, MOVE` pairs, terminated by another `db 0`. Level 0 means the move is known at level 1 (starting move). The engine uses this block at every level-up check, scanning from the current entry until it hits the terminator.

### Egg moves

Egg moves are a separate pointer table in `data/egg_move_pointers.asm`, which exports `EggMovePointers::`. The data lives in `data/egg_moves.asm`. Each species entry is simply a `db`-terminated list of move IDs:

```asm
; data/egg_moves.asm
BulbasaurEggMoves:
    db WRAP
    db CHARM
    db STRING_SHOT
    db AMNESIA
    db $ff          ; terminator

NoEggMoves:
    db $ff          ; shared terminator for species with no egg moves
```

Species with no egg moves point to the shared `NoEggMoves` label. The pointer table has one entry per species; for evolution families, typically only the base form has an entry — evolved forms share `NoEggMoves`.

---

## 4.4 Move Data

### The `move` macro

All move definitions live in `battle/moves/moves.asm` under the label `Moves::`. The file defines a local `move` macro at the top:

```asm
; battle/moves/moves.asm
MACRO move
    db \1 ; animation ID
    db \2 ; effect constant (EFFECT_*)
    db \3 ; base power (0 for status moves)
    db \4 | (\5 << 6) ; type + damage category packed into one byte
    db \6 ; accuracy (255 = never misses)
    db \7 ; PP
    db \8 ; effect chance (0 = no secondary chance / always applies)
ENDM
```

Each entry is 7 bytes. A few representative entries:

```asm
    move POUND,        EFFECT_NORMAL_HIT,    40, NORMAL,   PHYSICAL,  100, 35, 0
    move TOXIC,        EFFECT_TOXIC,          0, POISON,   STATUS,     85, 10, 0
    move FIRE_PUNCH,   EFFECT_BURN_HIT,      75, FIRE,     PHYSICAL,  100, 15, 10
```

Notice that type and damage category are packed into one byte using a bitshift: the lower 6 bits hold the type constant, bits 6–7 hold the category (`PHYSICAL`, `SPECIAL`, `STATUS`). This packing means neither field can exceed 63, which is satisfied by Prism's type and category counts.

### Effect dispatch

The `EFFECT_*` constant in each move record is an index into a jump table. Effect implementations live in `battle/moves/move_effects.asm`; the jump table that maps effect IDs to handler addresses is in `battle/moves/move_effects_pointers.asm`. Chapter 8 covers how the battle engine dispatches through that table and what the effect handler protocol looks like. From the data perspective, all that matters here is that the move record's effect byte is an 8-bit index — which caps the move effect count at 256.

---

## 4.5 Trainer Data

Trainer data splits across three layers: the **party group file** (the Pokémon), the **class attributes record** (AI flags, held items, prize money), and the **pointer table** that ties them together.

### Party groups

Each trainer class has a group file under `trainers/groups/`. The group file is a linear sequence of trainer entries, one per trainer in that class. Each entry begins with the trainer's name string (terminated by `@`), followed by a `TRAINERTYPE_*` flag byte, then the party, then `$ff` (or `db -1`) to mark the end of the party.

The `TRAINERTYPE_*` flag controls how many bytes follow each Pokémon slot:

| Constant | Value | Party entry format |
|----------|-------|--------------------|
| `TRAINERTYPE_NORMAL` | 0 | `db LEVEL, SPECIES` |
| `TRAINERTYPE_MOVES` | 1 | `db LEVEL, SPECIES` + 4 move bytes |
| `TRAINERTYPE_ITEM` | 2 | `db LEVEL, SPECIES, ITEM` |
| `TRAINERTYPE_ITEM \| TRAINERTYPE_MOVES` | 3 | `db LEVEL, SPECIES, ITEM` + 4 move bytes |

A simple Youngster entry:

```asm
; trainers/groups/youngster.asm
YoungsterGroup:
    ; 1
    db "Jordan@"
    db TRAINERTYPE_NORMAL
    db 4, TAILLOW
    db 4, PIDGEY
    db -1
```

A trainer with custom moves (from `trainers/groups/andre.asm`):

```asm
AndreGroup:
    ; 1
    db "Andre@"
    db TRAINERTYPE_MOVES
    db 31, MACHOKE
        db MACH_PUNCH, BULK_UP, SEISMIC_TOSS, FOCUS_ENERGY
    db 32, GALLADE
        db FUTURE_SIGHT, X_SCISSOR, SIGNAL_BEAM, DRAININGKISS
    ; ...
    db -1
```

The indentation of the move bytes is a readability convention, not syntactically significant.

### The pointer table and constant alignment

`trainers/trainer_pointers.asm` exports `TrainerGroups:`, a flat `dw` table — one pointer per class, in the same order as the `trainerclass` constants in `constants/trainer_constants.asm`:

```asm
; trainers/trainer_pointers.asm
TrainerGroups:
    dw JosiahGroup
    dw BrooklynGroup
    dw RinjiGroup
    ; ...
    dw YoungsterGroup
    ; ...
```

The `trainerclass` macro in `macros/trainer.asm` assigns each class an enum value and resets the per-class ID counter to 1:

```asm
; macros/trainer.asm
MACRO trainerclass
    enum \1
const_value = 1
ENDM
```

At runtime, `ReadTrainerParty` in `trainers/read_party.asm` receives a group byte (0-based index into `TrainerGroups`) and a trainer ID (1-based). It dereferences the group pointer, then scans forward through the group data counting `$ff` terminators until it has skipped (ID − 1) entries. The order of `trainerclass` declarations must exactly match the order of `dw` entries in `trainer_pointers.asm` — there is no name-to-pointer lookup; the index is everything.

Everything in `TrainerGroups` and all group data must live in the same ROM bank (currently bank `$74`), because the pointers are plain 16-bit `dw` values with no bank byte.

### Class attributes

Each class also has a fixed-size attributes record in `trainers/attributes.asm`, one per class in the same order. The `item_attribute` macro is not used here; the fields are bare `db`/`dw` directives:

```asm
; trainers/attributes.asm (one class entry)
    db HYPER_POTION, 0  ; up to two held items the trainer can use mid-battle
    db 25               ; base prize money multiplier
    dw AI_BASIC + AI_SETUP + AI_SMART + AI_AGGRESSIVE + AI_CAUTIOUS + AI_STATUS + AI_RISKY
    dw CONTEXT_USE + SWITCH_SOMETIMES
```

The AI flags are bitmasks defined in `constants/trainer_constants.asm`. The engine ORs them together to determine which AI routines run each turn when this class is battled.

---

## 4.6 Item Attributes

Item data lives in `items/`. The main table is `items/item_attributes.asm`, which defines and immediately uses a local `item_attribute` macro:

```asm
; items/item_attributes.asm
MACRO item_attribute
; (name ignored), price, held effect, parameter, property, pocket, field menu, battle menu
    dw \2           ; shop price (0 = unsellable / not in shops)
    db \3, \4, \5, \6
    dn \7, \8       ; field-menu type + battle-menu type packed as nibbles
ENDM
```

The macro comment labels the parameters; the first argument (item name) is present for readability but produces no bytes — it is never referenced by `\1` in the body. The binary record is 8 bytes: a 2-byte price, four 1-byte fields, and a nibble pair.

A representative cross-section:

```asm
ItemAttributes:
    item_attribute Master Ball,   0, HELD_NONE,         0, CANT_SELECT, BALL, ITEMMENU_NOUSE, ITEMMENU_CLOSE
    item_attribute Potion,      300, HELD_NONE,        20, CANT_SELECT, ITEM, ITEMMENU_PARTY, ITEMMENU_PARTY
    item_attribute Bicycle,       0, HELD_NONE,         0, CANT_TOSS,   KEY_ITEM, ITEMMENU_CLOSE, ITEMMENU_NOUSE
    item_attribute Metal Powder, 10, HELD_METAL_POWDER,10, CANT_SELECT, ITEM, ITEMMENU_NOUSE, ITEMMENU_NOUSE
```

The `property` field encodes toss/select restrictions (`CANT_SELECT`, `CANT_TOSS`). The pocket constant (`BALL`, `ITEM`, `KEY_ITEM`, `POCKETTYPE_TMHM`) routes the item to the correct bag tab. The two menu-use fields control whether the item appears in the field bag menu and the in-battle menu, and what action selecting it triggers (`ITEMMENU_PARTY`, `ITEMMENU_CLOSE`, `ITEMMENU_NOUSE`).

Held-item effects are implemented separately: `HELD_*` constants index into a held-effect handler table in the battle engine. The `parameter` byte is passed to that handler as a magnitude (e.g., 20 for Potion's heal amount, 10 for Metal Powder's stat boost).

### Mart inventories

Shop stock is stored as simple pointer tables in `items/marts.asm`. `Marts:` is a `dw` table of pointers to inventory lists. Each list is a length byte, followed by that many item constants, followed by `$ff`:

```asm
; items/marts.asm
CaperMartItems:
    db 5          ; item count
    db POKE_BALL
    db POTION
    db ANTIDOTE
    db ESCAPE_ROPE
    db REPEL
    db $ff
```

The mart index used at runtime is passed to the shop engine via script command; it dereferences `Marts` to find the right list, then renders it as a menu. The lists are purely data — there is no logic for conditionally unlocking items at runtime beyond swapping out which mart pointer a town's NPC uses.

---

## 4.7 Wild Encounter Tables

Wild Pokémon data is split across several region-specific files under `data/wild/`. The engine file `engine/wildmons.asm` assembles them into separate labelled sections (`NaljoGrassWildMons`, `RijonGrassWildMons`, etc.) and provides the `wildmap` macro that wraps each map's block.

### The grass record format

Grass encounter data uses the `wildmap` macro to mark the start of each map's block, followed by three encounter-rate bytes (morning / day / night), then the Pokémon slots:

```asm
; data/wild/naljo_grass.asm (one map's entry)
    wildmap ACQUA_START
    db 2 percent, 2 percent, 2 percent   ; encounter rates morn/day/nite
    ; morning slots (7 entries: db LEVEL, SPECIES)
    db 2, SHINX
    db 2, MAKUHITA
    db 2, SENTRET
    db 2, VENONAT
    db 2, ABRA
    db 2, ZUBAT
    db 2, ZUBAT
    ; day slots (7 entries)
    db 2, SHINX
    ; ...
    ; night slots (7 entries)
    db 2, SHINX
    ; ...
```

There are exactly 7 slots per time-of-day segment and 3 segments, giving 21 Pokémon entries (42 bytes) plus the 3 rate bytes plus 2 bytes for the map header — a total of 47 bytes per grass block. This is the `GRASS_WILDDATA_LENGTH` constant defined in `constants/pokemon_data_constants.asm`:

```asm
NUM_GRASSMON EQU 7
GRASS_WILDDATA_LENGTH EQU (NUM_GRASSMON * 2 + 1) * 3 + 2
```

The assembler enforces this with an `assert` inside the `wildmap` macro: if a map's previous block is the wrong size, the build fails with an error naming the offending map. This is a good example of using the assembler as a data validator — no runtime check needed.

Water encounter tables follow the same structure but with 3 slots per time-of-day (`NUM_WATERMON EQU 3`), reflected in `WATER_WILDDATA_LENGTH`. Fishing encounters live in `data/wild/fish.asm` with their own slot count.

### What this chapter does not cover

The encounter tables describe *what* can be found and *where*. The scripting and overworld engine decides *when* to trigger an encounter check — step counter, tall grass detection, surfing state. That runtime behaviour is the domain of Chapter 7. Similarly, roaming Pokémon (Suicune, Entei, Raikou) have their own roam-map tables in `engine/wildmons.asm` (`roam_map` macro), but their movement and encounter logic is again an engine concern outside this chapter's scope.

---

## Where to Next

You now have a map of the static content that defines Prism's game world — every species, move, trainer, item, and encounter slot exists as a row in one of the tables described here. What you do not yet have is a concrete picture of how those species and encounters are embedded in a playable location.

[Chapter 5 — Anatomy of a Map](05-anatomy-of-a-map.md) takes a single map from constants through block grid to header records, showing how the engine uses two-level pointer tables to find a map's tileset, dimensions, scripts, and NPC list from nothing more than a group-and-number pair.
