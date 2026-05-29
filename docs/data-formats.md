# Data Formats

Struct layouts for the major data tables. Use this when reading or writing
Pokémon stats, trainer parties, moves, or items.

---

## Pokémon Base Stats (`data/base_stats/<name>.asm`)

One file per species, collected by `data/base_stats.asm`.

```asm
; data/base_stats/pikachu.asm
db PIKACHU          ; species constant (from constants/pokemon_constants.asm)

; Base stats (one byte each)
db 35               ; HP
db 55               ; Attack
db 40               ; Defense
db 50               ; Special Attack
db 50               ; Special Defense
db 90               ; Speed

db ELECTRIC, ELECTRIC   ; type1, type2 (same = mono-type)
db 190                  ; catch rate
db 112                  ; base EXP yield

; Held items (ITEM_NONE = no item)
db ITEM_LIGHT_BALL      ; common held item (255/256 chance)
db ITEM_NONE            ; rare held item  (1/256 chance)

db 127                  ; gender ratio  (0=always male, 254=always female,
                        ;                255=genderless, 127=50/50)
db 0                    ; unknown / step cycles for egg hatching multiplier
db 10                   ; egg cycles (hatch steps = value * 256)

INCLUDE "gfx/pics/pikachu/dimensions.asm"   ; front/back sprite size

db ABILITY_STATIC       ; ability 1
db ABILITY_LIGHTNING_ROD ; ability 2 (ABILITY_NONE if only one)

db GROWTH_MEDIUM_FAST   ; EXP growth rate

dn EGG_FIELD, EGG_FAIRY ; egg groups (two nibbles packed via dn macro)
```

### Growth rate constants (`constants/pokemon_constants.asm`)
`GROWTH_MEDIUM_FAST`, `GROWTH_MEDIUM_SLOW`, `GROWTH_FAST`, `GROWTH_SLOW`,
`GROWTH_ERRATIC`, `GROWTH_FLUCTUATING`

---

## Evolution & Learnset (`data/evos_attacks.asm`)

```asm
PikachuEvosAttacks:
    ; Level-up moves: db LEVEL, MOVE_*  (level 0 = starting move)
    db 0,  MOVE_THUNDERSHOCK
    db 0,  MOVE_GROWL
    db 6,  MOVE_TAIL_WHIP
    db 8,  MOVE_THUNDER_WAVE
    ; ...
    db 0, 0    ; terminator

    ; Evolutions: db EVO_METHOD, <args>, EVOLVED_SPECIES
    db EVO_ITEM, ITEM_THUNDER_STONE, RAICHU
    db 0        ; evolution terminator
```

Evolution method constants (`EVO_*`) are in `constants/pokemon_constants.asm`.

---

## Trainer Party (`trainers/groups/<ClassName>.asm`)

Format depends on the `TRAINERTYPE_*` flags set in the trainer header.

### Simple (level + species only)
```asm
TrainerName:
    db "TRAINER NAME@"
    db 0                    ; TRAINERTYPE flags (0 = simple)
    db LEVEL, SPECIES
    db LEVEL, SPECIES
    db $ff                  ; party terminator
```

### With custom moves (`TRAINERTYPE_MOVES`)
```asm
    db TRAINERTYPE_MOVES
    db LEVEL, SPECIES
        db MOVE_1, MOVE_2, MOVE_3, MOVE_4
    db $ff
```

### With held items (`TRAINERTYPE_ITEM`)
```asm
    db TRAINERTYPE_ITEM
    db LEVEL, SPECIES, ITEM_*
    db $ff
```

### With both (`TRAINERTYPE_ITEM | TRAINERTYPE_MOVES`)
```asm
    db TRAINERTYPE_ITEM | TRAINERTYPE_MOVES
    db LEVEL, SPECIES, ITEM_*
        db MOVE_1, MOVE_2, MOVE_3, MOVE_4
    db $ff
```

---

## Move Data (`battle/moves/moves.asm`)

```asm
; One entry per move, collected into a table
Move_Tackle:
    db MOVE_TACKLE          ; move ID
    db EFFECT_NORMAL_HIT    ; effect (from constants/battle_constants.asm)
    db 35                   ; base power (0 = status move)
    db NORMAL               ; type
    db 100                  ; accuracy (255 = never misses)
    db 35                   ; PP
    db 0                    ; effect chance (0 = effect always happens / no chance)
```

Move effect IDs are defined in `constants/battle_constants.asm` as `EFFECT_*`.
Effect implementations live in `battle/moves/move_effects.asm` with a jump
table in `battle/moves/move_effects_pointers.asm`.

---

## Item Attributes (`items/item_attributes.asm`)

```asm
; One entry per item ID
ItemAttributes_MasterBall:
    db ITEM_MASTER_BALL     ; item ID
    dw 0                    ; price (0 = not sold)
    db HELD_EFFECT_NONE     ; held-item effect ID
    db 0                    ; held-item power parameter
    db ITEMMENU_NOUSE       ; field use type
    db 0                    ; battle use type
    db POCKETTYPE_BALL      ; bag pocket
    db 1                    ; flags (bit 0 = key item, bit 1 = usable in battle)
```

Pocket type constants: `POCKETTYPE_ITEM`, `POCKETTYPE_BALL`, `POCKETTYPE_KEY`,
`POCKETTYPE_TMHM` (in `constants/item_constants.asm`).

---

## Wild Encounter Tables (`data/wild/<MapName>.asm`)

```asm
MapNameMons:
    db GRASS_WILDMONS       ; encounter type constant
    db ENCOUNTER_RATE       ; encounter rate (0 = no encounters)

    ; Ten slots: db LEVEL_MIN, LEVEL_MAX, SPECIES
    db  3,  5, RATTATA
    db  3,  5, PIDGEY
    ; ... (10 slots total for grass)

    db SURF_WILDMONS
    db SURF_RATE
    ; Five slots for surfing encounters
    db 10, 20, TENTACOOL
    ; ...

    db -1   ; terminator
```

---

## Pokémon Party Struct (in WRAM)

The in-memory struct for a party Pokémon. Field offsets are defined as `MON_*`
constants in `constants/wram_constants.asm` and accessed via helpers in
`home/pokemon_data.asm`.

| Offset | Size | Field |
|--------|------|-------|
| `MON_SPECIES` | 1 | Species ID |
| `MON_ITEM` | 1 | Held item |
| `MON_MOVES` | 4 | Move IDs (4 bytes) |
| `MON_ID` | 2 | Original trainer ID |
| `MON_EXP` | 3 | EXP points (24-bit) |
| `MON_EVS` | 10 | EV stats (HP/Atk/Def/SpA/SpD/Spe, 2 bytes each) |
| `MON_DVS` | 2 | DVs (old-style IVs packed 4 bits each) |
| `MON_PP` | 4 | PP per move |
| `MON_HAPPINESS` | 1 | Friendship value |
| `MON_POKE_PK2` | 1 | PKrus status |
| `MON_CAUGHT_DATA` | 1 | Caught location/time packed byte |
| `MON_LEVEL` | 1 | Current level |
| `MON_STATUS` | 1 | Status condition |
| `MON_UNUSED` | 1 | Padding |
| `MON_HP` | 2 | Current HP |
| `MON_MAXHP` | 2 | Max HP |
| `MON_ATK` | 2 | Attack stat |
| `MON_DEF` | 2 | Defense stat |
| `MON_SPE` | 2 | Speed stat |
| `MON_SPATK` | 2 | Special Attack stat |
| `MON_SPDEF` | 2 | Special Defense stat |

Use `GetPartyMonData` / `SetPartyMonData` (via `predef`) to read/write fields
by `MON_*` constant rather than accessing WRAM offsets directly.

---

## Text Format

Dialogue strings use a custom character encoding (defined in `macros/charmap.asm`).
Special control bytes:

| Macro | Meaning |
|-------|---------|
| `text "string"` | Start a text block |
| `line "string"` | Second line (scroll up) |
| `cont "string"` | Continuation after button press |
| `para "string"` | New paragraph (clears box) |
| `done` | End text block |
| `page` | Alias for para |
| `@` | In raw `db` — string terminator |

Special inline bytes: `<PLAYER>` → player name, `<MON>` → Pokémon name,
`<RIVAL>` → rival name. These are 1-byte placeholders expanded at print time.
