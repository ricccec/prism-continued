# Maps and Events

How the 461 maps are defined, how event scripting works, and how to add or
modify map content.

---

## Map File Structure

Every map lives in `maps/<MapName>.asm`. Each file follows this layout:

```asm
INCLUDE "macros/map.asm"    ; usually pulled in via includes.asm

; ── Script header ──────────────────────────────────────────────────────────
MapName_MapScriptHeader:
    db <trigger_count>       ; number of on-load trigger scripts
    db <callback_count>      ; number of persistent callbacks
    dbw TRIGGER_AUTO, .Trigger0    ; priority, pointer  (one per trigger)
    dbw CB2_OVERWORLD, .Callback   ; priority, pointer  (one per callback)

.Trigger0:
    ; script bytecode (see Event Scripting below)
    end

.Callback:
    end

; ── NPC dialogue and object scripts ────────────────────────────────────────
MapName_ObjectScripts:

.NPC1Text:
    text "Hello!"
    done

; ── Event header ───────────────────────────────────────────────────────────
MapName_MapEventHeader::
    db 0                      ; filler (always 0)
    db 0                      ; filler (always 0)

.Warps
    db <warp_count>
    warp_def <y>, <x>, <dest_index>, DESTINATION_MAP_CONST

.CoordEvents
    db <coord_count>
    coord_event <y>, <x>, <script_flag>, <script_ptr>

.BGEvents
    db <bg_count>
    signpost <y>, <x>, SIGNPOST_TYPE, <text_or_script_ptr>

.ObjectEvents
    db <object_count>
    person_event SPRITE_ID, <y>, <x>, SPRITEMOVEDATA_TYPE, \
                 <palette>, OBJECTTYPE_NORMAL, <text_ptr>, \
                 <function_ptr>, EVENT_OPTIONAL_FLAG
```

### `warp_def` fields

```
warp_def <y>, <x>, <dest_index>, MAP_CONST
```
`dest_index` indexes into the destination map's own `.Warps` list (0-based).
To land at the first warp of the destination, use 0.

### `person_event` fields

```
person_event SPRITE, y, x, MOVEMENT, PALETTE, TYPE, TEXT, FUNCTION, FLAG
```

| Field | Values |
|-------|--------|
| `SPRITE` | `SPRITE_*` constant from `constants/sprite_constants.asm` |
| `MOVEMENT` | `SPRITEMOVEDATA_*` — stationary, wander, follow, etc. |
| `PALETTE` | `PAL_NPC_*` |
| `TYPE` | `OBJECTTYPE_NORMAL`, `OBJECTTYPE_TRAINER`, `OBJECTTYPE_ITEM`, … |
| `TEXT` | Pointer to a text block or script |
| `FUNCTION` | Extra function pointer (often -1 / `$ff`) |
| `FLAG` | `EVENT_*` flag — object hidden when flag is set; use `$0` for always-visible |

### `signpost` types

| Constant | Behaviour |
|----------|-----------|
| `SIGNPOST_READ` | Show text on A-press |
| `SIGNPOST_UP` | Trigger only facing up |
| `SIGNPOST_ITEM` | Contains hidden item |
| `SIGNPOST_SCRIPT` | Run a script instead of text |

---

## Event Scripting

Scripts are bytecode sequences interpreted by `home/scripting.asm` with command
implementations in `engine/scripting.asm`.

### Common script commands

```asm
; Control flow
scall   <ptr>               ; call sub-script (returns)
sreturn                     ; return from scall
end                         ; end script, resume normal play
jump    <ptr>               ; unconditional jump
jumptrue   <ptr>            ; jump if last check was true
jumpfalse  <ptr>            ; jump if last check was false
if_equal   <val>, <ptr>     ; compare and branch

; Flags
setevent   <EVENT_FLAG>     ; set an event flag permanently
resetevent <EVENT_FLAG>     ; clear an event flag
checkflag  <EVENT_FLAG>     ; set Z if flag is set (use with jumptrue)
setvar     <id>, <val>      ; set a script variable
checkvar   <id>, <val>      ; compare a script variable

; Text / UI
opentext                    ; lock player, open text box
writetext  <ptr>            ; queue text for display
waittext                    ; wait for player to dismiss
closetext                   ; close text box, unlock player
yesorno                     ; yes/no prompt, sets carry on "yes"

; Items / Pokémon
giveitem   <ITEM_*>, <qty>  ; add item to bag
takeitem   <ITEM_*>, <qty>  ; remove item from bag
checkitem  <ITEM_*>         ; true if player has item
givemon    <species>, <lvl> ; add Pokémon to party
givetm     <TM_id>          ; give TM disc

; Map control
warp      <map>, <warp_id>  ; teleport player
special   <SPECIAL_*>       ; call a special function by ID
```

### Script variable IDs

Script variables are single-byte values stored in `wSpriteMovementByte` area.
Common IDs are defined in `constants/script_constants.asm`.

### Trigger priorities

`TRIGGER_AUTO` fires once when the map loads.
`CB2_OVERWORLD` fires every frame while in overworld.
Multiple triggers execute in order of their `priority` byte (lower = first).

---

## Map Constants

Map IDs are defined in `constants/map_constants.asm` as `MAP_*` constants and
grouped by region. The grouping also determines which map data section they
belong to in the linker script.

Map block data (visual tiles) is kept separate from map scripts — block data
lives in banks $20–$35, scripts in $36–$44.

---

## Map Connections

Connections define the scrolling seams between adjacent outdoor maps. They are declared in `maps/second_map_headers.asm` immediately after the `map_header_2` for the map:

```asm
map_header_2 CaperRidge, CAPER_RIDGE, 53, NORTH | EAST
connection north, ROUTE_70,       Route70,      5, 0, 10, CAPER_RIDGE
connection east,  ROUTE_71_WEST,  Route71West,  0, 0,  9, CAPER_RIDGE
```

### `connection` fields

```
connection <direction>, <neighbor_id>, <neighbor_label>, <edge_offset>, <neighbor_offset>, <strip_length>, <this_map_id>
```

| Field | Meaning |
|-------|---------|
| `direction` | `north`, `south`, `east`, or `west` |
| `neighbor_id` | Neighbor's map-group constant — provides `GROUP_*`, `MAP_*`, `*_WIDTH`, `*_HEIGHT` |
| `neighbor_label` | Unused (will eventually merge with `neighbor_id`) |
| `edge_offset` | Column (N/S) or row (E/W) along *this* map's edge where the seam starts |
| `neighbor_offset` | Column (N/S) or row (E/W) along the neighbor's opposite edge where the strip begins |
| `strip_length` | How many tiles wide (N/S) or tall (E/W) the visible seam window is |
| `this_map_id` | This map's own constant — provides `*_WIDTH`, `*_HEIGHT` for camera offset calculation |

The connection bitmask in `map_header_2`'s last argument (`NORTH | EAST`) must include a bit for every `connection` you declare; valid bits are `NORTH`, `SOUTH`, `EAST`, `WEST`.

### Alignment diagram

`edge_offset` and `neighbor_offset` describe how the two maps line up along the shared edge.

**North/South** — offsets are columns (x), strip_length is width:

```
col:  0   1   2   3   4   5   6   7   8   9  10  11  12
      [         Route 73 (neighbor, to the north)       ]
                  [     Oxalis City (this map)     ]
                  ^                               ^
           edge_offset=5                  5+strip_length=17
      ^
 neighbor_offset=0

connection north, ROUTE_73, Route73, 5, 0, 12, OXALIS_CITY
```

Oxalis City's left edge is 5 tiles to the right of Route 73's left edge.
The engine copies a 12-tile-wide strip from Route 73's bottom rows into
Oxalis City's north border.

**East/West** — offsets are rows (y), strip_length is height:

```
row:  0  [  Route 68  |  Acania Docks  ]
row:  1  [  Route 68  |  Acania Docks  ]  ← edge_offset=1, neighbor_offset=0
row:  2  [  Route 68  |  Acania Docks  ]
         ...10 rows tall (strip_length=10)

connection west, ACANIA_DOCKS, AcaniaDocks, 1, 0, 10, ROUTE_68
```

Route 68's west border starts 1 row below Acania Docks' top edge.

### Alignment invariant

`(edge_offset − neighbor_offset) × −2` is encoded as the camera-alignment byte so the camera shifts smoothly when crossing the border. Reciprocal connections must have opposite deltas:

```asm
; From Oxalis City north to Route 73:  delta = 5 − 0 = +5
connection north, ROUTE_73, Route73, 5, 0, 12, OXALIS_CITY

; From Route 73 south to Oxalis City:  delta = −3 − 2 = −5  (always opposite)
connection south, OXALIS_CITY, OxalisCity, -3, 2, 19, ROUTE_73
```

---

## Adding a New Map

1. Create `maps/NewMapName.asm` following the structure above.
2. Include `maps/NewMapName.asm` in `maps/map_scripts.asm`.
3. Add the map header to `maps/map_headers.asm`.
4. Add the secondary header to `maps/second_map_headers.asm` (can be in any bank).
5. Add width/height to `constants/map_dimension_constants.asm`.
6. Add the map's `INCBIN` for block data in `maps/blockdata.asm` (blk file can be anywhere; label must end with `_BlockData`).
7. Ensure the linker script (`contents/romx.link`) has capacity in the target bank.

The script header label must end with `_MapScriptHeader`; the event header label must end with `_MapEventHeader`.

---

## Overworld Sprite Movement Types

Defined in `constants/sprite_constants.asm` as `SPRITEMOVEDATA_*`:

| Constant | Behaviour |
|----------|-----------|
| `SPRITEMOVEDATA_SPINRANDOM_SLOW` | Spin randomly, slow |
| `SPRITEMOVEDATA_WALK_LEFT_RIGHT` | Pace left-right |
| `SPRITEMOVEDATA_WALK_UP_DOWN` | Pace up-down |
| `SPRITEMOVEDATA_WANDER_AROUND` | Random wander in small area |
| `SPRITEMOVEDATA_STATIONARY` | Never moves |
| `SPRITEMOVEDATA_POKEMON` | Wild Pokémon (special behavior) |
| `SPRITEMOVEDATA_FOLLOWER` | Follow the player |

---

## Trainer NPC Setup

Trainer NPCs use `OBJECTTYPE_TRAINER`:

```asm
person_event SPRITE_LASS, 10, 14, SPRITEMOVEDATA_WALK_LEFT_RIGHT, \
             PAL_NPC_RED, OBJECTTYPE_TRAINER, .TrainerText, \
             TrainerLassGroupPointer, EVENT_TRAINER_LASS_1
```

The trainer's party data lives in `trainers/groups/<ClassName>.asm`.
`TrainerLassGroupPointer` is a `dba` (bank+address) pointing to that data.
See [data-formats.md](data-formats.md) for the party format.
