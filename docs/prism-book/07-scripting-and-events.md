# Chapter 7 — The Scripting VM & Events

*A map without events is a painting. Events are what make it a place.*

---

If Chapters 5 and 6 showed you what a map *is* — the block grid, the tileset, the headers, the palette system — this chapter shows you what a map *does*. Doors that teleport you. NPCs that pace back and forth and then turn to face you when you press A. A sign that slides in from the bottom of the screen when you cross an invisible boundary. Grass that tries to start a fight with you every few steps. All of that lives here.

The systems that power the interactive overworld are layered. At the outermost edge, the map script header declares what happens when the map loads and what happens on each frame. Deeper in, the scripting VM interprets variable-width bytecode to drive individual interactions. Orthogonally, the event header declares every warp, NPC, sign, and coordinate trigger. And the overworld loop — the frame driver in `engine/events.asm` — coordinates the whole ensemble sixty times a second.

This chapter walks through each layer in turn, then closes with a frame-by-frame tour of the loop.

---

## 7.1 The Map Script Header

Every map in Prism has a map script header. Its address is stored in the secondary header as a three-byte `dba` (bank + address), as we saw in Chapter 5. The secondary header macro emits:

```asm
; macros/map.asm — map_header_2
\1_SecondMapHeader::
    db \3               ; border block ID
    db \2_HEIGHT, \2_WIDTH
    dba \1_BlockData
    dba \1_MapScriptHeader  ; ← three bytes: bank + 16-bit address
    dw \1_MapEventHeader
    db \4               ; connection bitmask
```

The map script header itself has a fixed-prefix, variable-length format. Here is the header from `maps/AcaniaDocks.asm`, one of the simpler examples:

```asm
AcaniaDocks_MapScriptHeader:
    db 0    ; trigger count
    db 1    ; callback count

    dbw 5, AcaniaDocks_SetFlyFlag

AcaniaDocks_SetFlyFlag:
    setflag ENGINE_FLYPOINT_ACANIA_DOCKS
    return
```

The first byte is the number of **triggers**; the second is the number of **callbacks**. After those two bytes, triggers are listed first (each is a `dbw`: one-byte priority byte + two-byte pointer), then callbacks (same format). Here there are zero triggers and one callback at callback type `5`, which is `MAPCALLBACK_NEWMAP`.

### Callbacks

A callback is keyed to a **callback type**, a small integer defined in `constants/map_setup_constants.asm`:

```asm
const_value = 1
    const MAPCALLBACK_TILES      ; 1 — fired during LoadBlockData
    const MAPCALLBACK_OBJECTS    ; 2 — fired when NPCs are spawned
    const MAPCALLBACK_CMDQUEUE   ; 3 — fired after clearing the command queue
    const MAPCALLBACK_SPRITES    ; 4 — fired during sprite refresh
    const MAPCALLBACK_NEWMAP     ; 5 — fired when the map is first entered
```

The engine calls `RunMapCallback` (in `home/map.asm`) with the desired type in register `a`. That function iterates the callback list, comparing the type byte of each `dbw` entry against the requested type, and calls the first match's script via `ExecuteCallbackScript`. Each callback fires exactly once per occasion — there is no broadcast; only the first matching entry runs.

`MAPCALLBACK_NEWMAP` is the most common. It fires during the warp setup sequence after map metadata has been loaded (called from `RunCallback_05_03` in `engine/warp_connection.asm`). Almost every city-level map has a `MAPCALLBACK_NEWMAP` callback that sets a Fly-point engine flag:

```asm
; engine/warp_connection.asm
RunCallback_05_03:
    call ResetMapBufferEventFlags
    call ResetFlashIfOutOfCave
    call GetCurrentMapTrigger
    call ResetBikeFlags
    ld a, MAPCALLBACK_NEWMAP
    call RunMapCallback
    ; ...
```

`MAPCALLBACK_TILES` lets a map modify its own block data after decompression — used for puzzle maps that need to change blocks based on saved state before the camera sees anything. `MAPCALLBACK_OBJECTS` runs just before NPCs are spawned, letting scripts add or suppress objects programmatically.

### Triggers

Triggers are a different mechanism entirely. They are **one-shot, condition-driven** scripts: when the player enters a map, the engine checks whether a predetermined WRAM address holds a non-zero value and, if so, runs a script. The trigger table lives in `engine/map_triggers.asm`:

```asm
MapTriggers::
MACRO trigger_def
    map \1       ; db GROUP_\1, MAP_\1
    dw \2        ; WRAM pointer to trigger condition
ENDM

    trigger_def POKECENTER_BACKROOM,    wPokecenter2FTrigger
    trigger_def TRADE_CENTER,           wTradeCenterTrigger
    trigger_def BATTLE_CENTER,          wColosseumTrigger
    trigger_def ROUTE_69_SOUTH_GATE,    wRoute69SouthGateTrigger
    trigger_def MILOS_B1F,              wMilosB1FTrigger
    ; ... (40+ entries)
    trigger_def CAPER_RIDGE,            wCaperRidgeTrigger
    trigger_def ROUTE_34_GATE,          wRoute34GateTrigger
    trigger_def ROUTE_50_GATE,          wRoute50GateTrigger
    db -1
```

Each entry is three bytes: two bytes for the map group/number (via the `map` macro), and two bytes for the WRAM pointer to the trigger condition. The table is terminated by `db -1`. When the player enters any map listed here, `GetCurrentMapTrigger` (called from `RunCallback_05_03`) searches the table for the current map ID, loads the WRAM trigger byte, and stores it. Later, `DoMapTrigger` in `engine/events.asm` checks that byte and, if it is non-zero, dispatches to the appropriate script from the map script header's trigger section.

The trigger byte in WRAM is map-specific state — the game writes it before entering a map to describe what the map should do on arrival. It is how the game implements controlled entry sequences: the Route 69 badge check, the Battle Tower room progression, the Milos puzzle state. The trigger system is not a general per-frame check; it fires once per map entry, and only for maps listed in the `MapTriggers` table.

---

## 7.2 The Scripting VM

### Structure

Scripts are bytecode programs interpreted by two files working together. `engine/scripting.asm` contains the dispatcher loop, `ScriptEvents`, and the `ScriptCommandTable`. The state machine that governs the loop lives at the top of that file:

```asm
; engine/scripting.asm
ScriptEvents::
    ld a, [wScriptBank]
    ld [wInitialScriptBank], a
    ld a, [wScriptPos]
    ld [wInitialScriptPos], a
    ld a, [wScriptPos + 1]
    ld [wInitialScriptPos + 1], a
    call StartScript
.loop
    ld a, [wScriptMode]
    jumptable .modes
    call CheckScript
    jr nz, .loop
    ret

.modes
    dw StopScript        ; 0 — not running
    dw RunScriptCommand  ; 1 — read next command
    dw WaitScriptMovement; 2 — waiting for NPC to stop moving
    dw WaitScript        ; 3 — delay in progress
```

Each iteration of `.loop` jumps through one of four modes. `RunScriptCommand` is the hot path: it reads one byte from ROM at `wScriptBank:wScriptPos`, bounds-checks it against the table size, and dispatches through `ScriptCommandTable`:

```asm
RunScriptCommand:
    call GetScriptByte          ; a = next bytecode byte; advances wScriptPos
    cp (ScriptCommandTableEnd - ScriptCommandTable) / 2
    jr c, .go
    ld a, 9
    call Crash                  ; out-of-range opcode = hard crash
.go
    jumptable
ScriptCommandTable:
    dw Script_scall             ; 00 — call sub-script (saves return address)
    dw Script_farscall          ; 01 — call in another bank
    dw Script_ptcall            ; 02 — call via predef table
    dw Script_jump              ; 03 — unconditional jump
    dw Script_farjump           ; 04 — jump to another bank
    dw Script_ptjump            ; 05
    dw Script_if_equal          ; 06 — branch if var == value
    dw Script_if_not_equal      ; 07
    dw Script_iffalse           ; 08 — branch if last check was false
    dw Script_iftrue            ; 09
    dw Script_if_greater_than   ; 0a
    dw Script_if_less_than      ; 0b
    ; ... (extends to 0xeb, about 150 entries total)
    dw Script_checkevent        ; 31
    dw Script_clearevent        ; 32
    dw Script_setevent          ; 33
    dw Script_checkflag         ; 34
    dw Script_clearflag         ; 35
    dw Script_setflag           ; 36
    dw Script_giveitem          ; 1f
    dw Script_takeitem          ; 20
    dw Script_opentext          ; 46
    dw Script_writetext         ; 4b
    dw Script_yesorno           ; 4d
    dw Script_faceplayer        ; 6a
    dw Script_applymovement     ; 68
    dw Script_warp              ; 3a
    dw Script_startbattle       ; 5e
    dw Script_reloadmapafterbattle ; 5f
    ; ...
ScriptCommandTableEnd:
```

The VM is a pure fetch-dispatch loop. There is no stack frame, no local variables, no structured control flow in the bytecode — only flat jumps. `GetScriptByte` reads from `wScriptBank:wScriptPos` and advances the position pointer. The bytecode is variable-width: most commands take operands that follow the opcode byte, and each command handler consumes exactly as many additional bytes as it needs.

The current script position is stored in two WRAM bytes (`wScriptPos`/`wScriptPos+1`) plus a bank byte (`wScriptBank`). Sub-script calls push the return address onto a small internal stack. The `wScriptMode` byte controls whether the loop executes commands, waits for movement to complete, or waits out a delay timer.

### The `sif`/`sendif` Macro Layer

The bytecode has no structured `if`/`else`. In the source, however, you will constantly see `sif` / `sendif` blocks:

```asm
    checkevent EVENT_ACANIA_TM_44
    sif false, then
        opentext
        writetext .giveTM
        givetm TM_REST + RECEIVED_TM
        setevent EVENT_ACANIA_TM_44
    sendif
    jumptext .describeTM
```

`sif false, then` and `sendif` are macros defined in `macros/event.asm`. `sif false` emits a `siffalse_command` byte — opcode `$da` in the table. `then` inside `sif` emits a `then_command`, and `sendif` emits a `sendif_command` byte. At runtime, `Script_siffalse` in `engine/scripting.asm` delegates to `ScriptConditional` (a banked function), which reads the condition, and if the condition is *true* (i.e., the `false` branch should be skipped), it fast-forwards `wScriptPos` past `sendif`. If the condition is *false*, execution continues into the block normally. `Script_sendif` itself does nothing at runtime — it records a debugging note and returns immediately:

```asm
Script_sendif:
; purely a debugging statement
    ld a, [wScriptBank]
    ld [wLastSEndIfBank], a
    ; ... (save position for crash diagnostics)
    ret
```

So the macro layer gives scripts a legible, almost procedural appearance; the underlying bytecode is still flat jumps under a slightly friendlier face.

### A Real Script

Here is the complete NPC4 interaction from `maps/AcaniaDocks.asm`, verified against the source:

```asm
; maps/AcaniaDocks.asm
AcaniaDocksNPC4:
    faceplayer                      ; NPC turns to face you
    checkevent EVENT_ACANIA_TM_44   ; set condition: has this TM been given?
    sif false, then                 ; if NOT already given:
        opentext
        writetext .giveTM
        givetm TM_REST + RECEIVED_TM
        setevent EVENT_ACANIA_TM_44
    sendif
    jumptext .describeTM            ; either way, show the description

.giveTM:
    ctxt "The calm sea is"
    line "so relaxing."
    ; ... dialogue continues
    sdone

.describeTM:
    ctxt "TM44 is Rest."
    ; ...
    done
```

Reading this script and imagining the player's experience is one of the more satisfying affordances of the codebase. `checkevent` sets a condition flag. `sif false, then` reads that flag and either skips the indented block or executes it. `setflag`/`setevent` mark permanent state in a WRAM bitfield. `jumptext` is a tail-call: it jumps to a text label, displays it, and ends the script. The map file says what happens; the engine says how. Both layers are legible in the same source file.

---

## 7.3 Warps

### The `warp_def` Record

Every door, cave entrance, and building exit in Prism is a warp. Warps are declared in the map event header:

```asm
; maps/AcaniaDocks.asm
AcaniaDocks_MapEventHeader:: db 0, 0

.Warps:
    db 8
    warp_def 15,  7, 1, ACANIA_POKECENTER   ; (y, x, dest_warp_index, dest_map)
    warp_def  9,  3, 1, ACANIA_MART
    warp_def 19,  7, 1, ROUTE_81_NORTHGATE
    warp_def 19,  8, 2, ROUTE_81_NORTHGATE
    warp_def  9, 16, 1, ACANIA_GYM
    warp_def  5, 28, 1, ACANIA_LIGHTHOUSE_F1
    warp_def 15, 13, 1, ACANIA_HOUSE
    warp_def 11, 23, 1, ACANIA_TM63
```

The `warp_def` macro in `macros/map.asm` is exactly five bytes:

```asm
MACRO warp_def
    db \1 ; y
    db \2 ; x
    db \3 ; warp_to (destination warp index)
    map \4 ; db GROUP_\4, MAP_\4 — two bytes
ENDM
```

So five bytes total: Y, X, destination warp index, destination map group, destination map number. The destination warp index is the key to the whole system. It does not point directly to a tile; it refers to a numbered entry in the *destination map's own warp list*. "Take warp 1 of `ACANIA_POKECENTER`" means "land on the tile declared by `warp_def` #1 in the Pokécenter's `.Warps` section." Every warp has a mirror on the other side. Change which tile a door lands on? Update the entry warp's Y/X in the destination map file.

### Warp Discovery at Runtime

The engine discovers warps when the player steps onto a tile whose collision byte has the high-nibble warp convention (`$70`). `CheckWarpCollision` in `engine/tile_events.asm` is the gatekeeper:

```asm
CheckWarpCollision::
    ld a, [wPlayerStandingTile]
    cp COLL_HOLE
    jr z, .warp
    and $f0
    cp COLL_HIGH_NYBBLE_WARPS   ; = $70
    jr z, .warp
    and a
    ret
.warp
    scf
    ret
```

If carry is set, `GetDestinationWarpNumber` in `home/map.asm` walks the warp header looking for a Y/X match against the player's current position:

```asm
GetDestinationWarpNumber::
    callba CheckWarpCollision
    ret nc
    call StackCallInMapScriptHeaderBank
.GetDestinationWarpNumber:
    ld a, [wPlayerStandingMapY]
    sub 4           ; subtract camera offset
    ld e, a
    ld a, [wPlayerStandingMapX]
    sub 4
    ld d, a
    ld a, [wCurrMapWarpCount]
    and a
    ret z
    ld c, a
    ld hl, wCurrMapWarpHeaderPointer
    ld a, [hli]
    ld h, [hl]
    ld l, a
.loop
    push hl
    ld a, [hli]     ; Y of this warp entry
    cp e
    jr nz, .next
    ld a, [hli]     ; X of this warp entry
    cp d
    jr z, .found_warp
.next
    pop hl
    ld a, 5
    add l           ; advance by 5 (warp record size)
    ld l, a
    adc h \ sub l \ ld h, a
    dec c
    jr nz, .loop
    xor a
    ret             ; not found — no carry
.found_warp
    pop hl
    inc hl \ inc hl
    ; compute 1-based warp index in c, set carry
    ld a, [wCurrMapWarpCount]
    inc a
    sub c
    ld c, a
    scf
    ret
```

Once found, `CopyWarpData` reads the three remaining bytes of the matching record (dest warp index, map group, map number) and copies them into `wNextWarp`, `wNextMapGroup`, `wNextMapNumber`. From there the map setup sequence takes over (see Chapter 6).

### The `$ff` Return-to-Sender Convention

`CopyWarpData` has a special case: if the destination warp index byte is `$ff`, it substitutes the value stored in `wBackupWarpNumber` — the index of the warp the player *entered* the current map from:

```asm
CopyWarpData::
    call StackCallInMapScriptHeaderBank
.CopyWarpData
    ; ... navigate to the matched warp entry, skip 2 bytes to dest index
    ld a, [hli]
    cp $ff
    jr nz, .skip
    ld hl, wBackupWarpNumber
    ld a, [hli]     ; use the entry warp instead
.skip
    ld [wNextWarp], a
    ; ... copy map group and number
```

This is how cave exits work. The cave entrance's warp on the outside map points into the cave with a real warp index; the cave exit inside the cave uses `$ff`. When the player exits, the engine returns them to whichever warp they entered through, without the cave map needing to know anything about its callers.

### Directional Warps

`CheckDirectionalWarp` in `engine/tile_events.asm` intercepts tiles that should only warp when the player is moving in a specific direction — the gym carpet tiles, certain staircase tiles:

```asm
CheckDirectionalWarp::
    ld a, [wPlayerStandingTile]
    cp COLL_WARP_CARPET_DOWN
    jr z, .directional
    cp COLL_WARP_CARPET_LEFT
    jr z, .directional
    cp COLL_WARP_CARPET_UP
    jr z, .directional
    cp COLL_WARP_CARPET_RIGHT
    jr z, .directional
    scf
    ret             ; not directional — immediate warp (carry set)
.directional
    xor a
    ret             ; directional — clear carry, wait for direction check
```

If carry is clear, the tile event system holds off on the warp until the player's movement direction matches the tile's required direction.

---

## 7.4 Connections and the Scrolling Camera

Walking off the north edge of a route into a city is fundamentally different from walking through a door. There is no fade, no blackout, no pause. The world keeps scrolling. Chapter 5 showed how the 3-block border in `wOverworldMap` and `FillMapConnections` prepare the neighboring map's terrain in advance. This section covers what happens at the moment the player crosses the boundary.

### `EnterMapConnection`

When the player steps off a map edge, `CheckTileEvent` in `engine/events.asm` detects the move via `CheckMovingOffEdgeOfMap` and returns `PLAYEREVENT_CONNECTION`. The map setup sequence then calls `MapSetupScript_Connection` (from Chapter 6). One of its first steps is `EnterMapConnection` in `engine/warp_connection.asm`. Here is the east-direction case:

```asm
EnterEastConnection:
    ld a, [wEastConnectedMapGroup]
    ld [wMapGroup], a
    ld a, [wEastConnectedMapNumber]
    ld [wMapNumber], a
    ld a, [wEastConnectionStripXOffset]
    ld [wXCoord], a
    ld a, [wEastConnectionStripYOffset]
    ld hl, wYCoord
    add [hl]
    ld [hl], a
    ld c, a
    ld hl, wEastConnectionWindow
    ld a, [hli]
    ld h, [hl]
    ld l, a
    srl c
    jr z, .skip_to_load
    ld a, [wEastConnectedMapWidth]
    add 6
    ld e, a
    ld d, 0
.loop
    add hl, de
    dec c
    jr nz, .loop
.skip_to_load
    ld a, l
    ld [wOverworldMapAnchor], a
    ld a, h
    ld [wOverworldMapAnchor + 1], a
    scf
    ret
```

What this does: it writes the new map group/number into `wMapGroup`/`wMapNumber`, repositions the player's coordinates in the new map's space using the strip offsets, and — critically — repositions `wOverworldMapAnchor` to point into the correct row of `wOverworldMap`. That anchor is what the camera uses as its "current map origin". Since the neighbor's strip was already loaded into `wOverworldMap` during `FillMapConnections`, the block data is already there; only the anchor pointer needs to move.

After `EnterMapConnection`, the connection setup script runs `LoadMapAttributes` to refresh the WRAM metadata (warp list, NPC list, script header) for the new map, then `LoadObjectsRunCallback_02` to spawn the new map's NPCs, and `LoadMapPalettes` to update the colour table. No `DisableLCD`, no full VRAM reload, no screen fade — the blocks are already in `wOverworldMap`.

### The `connection` Macro's Alignment Math

When the secondary headers are assembled, `connection` records encode the exact strip alignment between neighbors. The macro in `macros/map.asm` for the north direction:

```asm
; macros/map.asm (north case)
; connection north, ROUTE_70, Route70, 5, 0, 10, CAPER_RIDGE
if !strcmp("\1", "north")
    dw wDecompressScratch + \2_WIDTH * (\2_HEIGHT - 3) + \5
    ; ^ source: bottom 3 rows of neighbour, offset by \5 columns
    dw wOverworldMap + \4 + 3
    ; ^ dest:   column \4 in this map's top border (3 rows from top)
    db \6                       ; strip length
    db \2_WIDTH                 ; neighbour width (for stride computation)
    db \2_HEIGHT * 2 - 1        ; used by FillMapConnections to advance rows
    db (\4 - \5) * -2           ; column alignment correction
    dw wOverworldMap + \2_HEIGHT * (\2_WIDTH + 6) + 1
```

The numbers — `ROUTE_70_WIDTH`, `CAPER_RIDGE_HEIGHT`, the offset and strip length — are all compile-time constants derived from `mapgroup` declarations. The pointer arithmetic is done at assemble time and baked into the ROM. At runtime, `FillMapConnections` just reads these pointers and does a memcopy; no arithmetic needed in the hot path.

### Scrolling Row/Column Pushes

The camera itself is a 32×32-tile BG layer on the GBC — a torus that wraps at both edges. The game maintains a sliding window into this torus. When the player steps, `ScrollMapDown`/`ScrollMapUp`/`ScrollMapLeft`/`ScrollMapRight` in `home/map.asm` push one new row or column of tile IDs from `wOverworldMap` into the BG tile map. The functions do this by calling `UpdateBGMapRow` or `UpdateBGMapColumn`, which write directly into VRAM during VBlank-safe windows. The hardware BG scroll registers (`rSCX`/`rSCY`) shift the visible viewport by up to one tile per step; pixel-level smoothness comes from the player sprite's sub-tile animation, which advances 2 pixels per frame for 8 frames. The entire motion is table-driven, with no per-pixel calculation on the CPU.

---

## 7.5 Object Events and NPCs

### The `person_event` Macro

Every NPC in a map is declared by `person_event` in the `.ObjectEvents` section of the map event header. The macro in `macros/map.asm` has variable syntax depending on the person type:

```asm
MACRO person_event
    db \1          ; sprite ID
    db \2 + 4      ; y (+ 4 for camera offset)
    db \3 + 4      ; x (+ 4 for camera offset)
    db \4          ; movement type
    dn \5, \6      ; clock_hour (high nibble), clock_daytime (low nibble)
    db \7          ; range / radius y
    db \8          ; range / radius x
    dn \9, \<10>   ; palette (high nibble), person type (low nibble)
    db \<11>       ; additional function-type nibble data
    IF \<10> == PERSONTYPE_JUMPSTD
        db \<12>   ; std index
        dw \<13>   ; event flag
    ELIF \<10> == PERSONTYPE_MART
        db \<12>   ; mart type
        db \<13>   ; mart ID
        dw \<14>   ; event flag
    ELSE
        dw \<12>   ; pointer to script / text
        dw \<13>   ; event flag (0 = always visible)
    ENDC
ENDM
```

The final two bytes — script pointer and event flag — are the interactive heart of the NPC. The event flag is a 16-bit index into the `wEventFlags` bitfield (the same bitfield that `setevent`/`checkevent` read). If the flag is non-zero and the corresponding bit is set, the NPC is **not spawned at all**. This is how the game handles NPCs that disappear after you talk to them, or trainers that are gone after you beat them.

From `maps/AcaniaDocks.asm`:

```asm
person_event SPRITE_LASS, 9, 9,
    SPRITEMOVEDATA_STANDING_DOWN, 0, 0, -1, -1,
    PAL_OW_RED, PERSONTYPE_SCRIPT, 0,
    AcaniaDocksNPC4, -1
```

`PERSONTYPE_SCRIPT` means the NPC's interaction runs a full script (as opposed to `PERSONTYPE_TEXTFP`, which just shows text and turns to face the player). The `-1` flag means this NPC is always visible.

### Spawning

When `LoadObjectsRunCallback_02` runs during map setup, it reads the NPC records from ROM and copies them into a fixed WRAM array — 13 object slots per map (`wMap1Object` through `wMap13Object`). The flag check at spawn time is the only filtering: if the flag is set, the slot is skipped. Once spawned, each WRAM slot holds the sprite ID, coordinates, movement state, and a pointer back to the ROM script data.

### Movement Types

After spawning, NPCs are updated every frame by a banked call to `HandleNPCStep` in `engine/map_objects.asm`. The movement type byte in the `person_event` record determines behavior:

| Constant | Behavior |
|----------|----------|
| `SPRITEMOVEDATA_STATIONARY` | Never moves; turns to face player on interaction |
| `SPRITEMOVEDATA_STANDING_DOWN` | Stationary, always faces down |
| `SPRITEMOVEDATA_WALK_LEFT_RIGHT` | Paces left-right a configurable distance |
| `SPRITEMOVEDATA_WALK_UP_DOWN` | Paces up-down |
| `SPRITEMOVEDATA_WANDER_AROUND` | Random wander in a small area |
| `SPRITEMOVEDATA_FOLLOWER` | Tracks the player step for step |
| `SPRITEMOVEDATA_SPINRANDOM_SLOW` | Spins to a random facing, slowly |

### Interaction

When the player presses A while facing an NPC, the engine finds the closest NPC in that facing direction, loads its script pointer and bank from the WRAM slot, and calls `CallScript`. The scripting VM takes over. For `PERSONTYPE_TEXT` the pointer goes directly to a text block. For `PERSONTYPE_SCRIPT` it is a full script. For `PERSONTYPE_TRAINER` the script uses the `trainer` macro, which expands into: check if already beaten (event flag), if not — initiate the trainer-spotted sequence, start the battle, handle win/loss dialogue. The actual battle engine handoff is via `Script_startbattle` (opcode `$5e`) followed by `Script_reloadmapafterbattle` (`$5f`). Chapter 9 covers what happens once the battle engine takes the wheel.

---

## 7.6 Coordinate Events and Wild Encounters

### Coordinate (XY) Triggers

Coordinate events — sometimes called coord events or xy_triggers — fire when the player stands on a specific tile. They are declared in the event header's `.CoordEvents` section using the `xy_trigger` macro:

```asm
; macros/map.asm
MACRO xy_trigger
    db \1 ; trigger number (used by CheckTriggers for activation control)
    db \2 ; y
    db \3 ; x
    IF _NARG == 5
        dw \5 ; event flag (must be clear to activate)
    ELSE
        dw 0
    ENDC
    dw \4 ; pointer to script
ENDM
```

Each record is 7 bytes: a trigger ID byte, Y, X, a 2-byte event flag, and a 2-byte script pointer. At runtime, `RunCurrentMapXYTriggers` in `home/map.asm` walks the XY trigger table, checks whether the player's position matches, optionally checks the event flag, and if both pass, calls the associated script. This is the mechanism behind invisible "step-on" events: story triggers that fire when you stand in the right spot, without any visible NPC or sign.

### The Tile Event Dispatch

The `CheckTileEvent` function in `engine/events.asm` is the step-on event hub. After every step:

```asm
; engine/events.asm — CheckTileEvent (simplified)
CheckTileEvent:
    ; 1. Check for map connection (walked off edge)
    callba CheckMovingOffEdgeOfMap
    jr c, .map_connection

    ; 2. Check for warp tile
    call CheckWarpTile
    jr c, .warp_tile

    ; 3. Check for coord events
    bit 1, [wScriptFlags3]
    call nz, RunCurrentMapXYTriggers
    ret c

    ; 4. Count steps (for poison/egg cycles)
    bit 0, [wScriptFlags3]
    jr z, .step_count_disabled
    call CountStep
    ret c

    ; 5. Check for random encounter
    bit 4, [wScriptFlags3]
    jr z, .ok
    call RandomEncounter
    ret c
.ok
    xor a
    ret
```

Steps 1–5 are checked in priority order. A warp tile pre-empts an XY trigger; an XY trigger pre-empts an encounter. The `wScriptFlags3` bits gate each check independently — `EnableWildEncounters` sets bit 4, connection detection uses bit 2, and so on. A Repel suppresses random encounters by halving the encounter rate at load time (see below); it does not turn off this check.

### Wild Encounters

Wild encounters are the final step in the per-step tile check. `RandomEncounter` rolls against the time-of-day encounter rate and, on success, selects a species from the encounter table loaded into WRAM by `LoadWildMonData`.

`LoadWildMonData` runs as part of every map setup sequence. It calls `_GrassWildmonLookup` to find the current map's entry in the region encounter table (one of `NaljoGrassWildMons`, `RijonGrassWildMons`, etc., selected by a `GrassPointerTable`). If found, it copies three bytes — morning rate, day rate, night rate — into `wMornEncounterRate`/`wDayEncounterRate`/`wNiteEncounterRate`. The full wild mon slot data (species and level ranges) stays in ROM; only the rates land in WRAM. At encounter-roll time, the engine selects the rate for the current time slot and compares it against a random byte.

`LoadWildMonData` also handles the Repel/Lure flute modifier via `wEncounterRateStage`:

```asm
; engine/wildmons.asm — LoadWildMonData
LoadWildMonData:
    ld a, 1
    ld [wEncounterRateStage], a  ; 1 = normal
LoadWildMonData_KeepFlutes:
    call _GrassWildmonLookup
    jr c, .copy
    ; no grass data — zero all three rates
    ld hl, wMornEncounterRate
    xor a
    ld [hli], a
    ld [hli], a
    ld [hl], a
    jr .done_copy
.copy
    inc hl \ inc hl     ; skip map ID bytes
    ld de, wMornEncounterRate
    ld bc, 3
    rst CopyBytes       ; copy morning/day/night rates
.done_copy
    call _WaterWildmonLookup
    ; ... copy water rate

    ; apply stage modifier
    ld a, [wEncounterRateStage]
    and a
    jr z, .halfRate     ; 0 = Repel — halve all rates (floor 1)
    dec a
    ret z               ; 1 = normal — done
    ; 2 = Lure — double all rates (cap $ff)
.loop
    ld a, [hl]
    add a
    jr nc, .noOverflow
    ld a, $ff
.noOverflow
    ld [hli], a
    dec c
    jr nz, .loop
    ret
.halfRate
    srl [hl]
    jr nz, .notZero
    inc [hl]            ; never let a non-zero rate halve to zero
.notZero
    inc hl
    dec c
    jr nz, .halfRate
    ret
```

The three stages are 0 (Repel: halve, floor 1), 1 (normal: no change), 2 (Lure flute: double, cap `$ff`). The modification is applied at load time, not roll time: using a Repel and walking into a new map resets the rate correctly because `LoadWildMonData` runs fresh on every map entry. The encounter DATA format — species arrays, slot weights, fishing tables — is covered in Chapter 4; this section is only the runtime behavior.

---

## 7.7 Landmark Signs

When the player crosses from one named location into another by scrolling — stepping off Route 70 onto Caper Ridge, or from Route 69 into Heath Village — a three-tile-tall sign slides up from the bottom edge of the screen, holds for two seconds, then slides back down. The location name is centered on it. This animation lives almost entirely in `engine/landmarksigns.asm`.

### Queueing

The animation is queued during the connection map setup sequence. `MapSetupScript_Connection` includes a step:

```asm
mapsetup QueueLandmarkSignAnim
```

`QueueLandmarkSignAnim` checks three things before committing:

```asm
QueueLandmarkSignAnim:
    xor a
    ldh [hBGMapMode], a
    call GetMapPermission
    cp GATE
    jr z, .cancel       ; gates never show a sign
    call GetCurWorldMapLocation  ; get landmark ID from primary header
    and a
    jr z, .cancel       ; landmark 0 = no sign
    cp DUMMY2
    jr c, .landmark_okay
    cp DUMMY4 + 1
    jr c, .cancel       ; DUMMY landmarks are suppressed
    cp MYSTERY_LANDMARK
    jr nc, .cancel      ; mystery zones are suppressed
.landmark_okay
    ld [wCurrentLandmark], a
    ld hl, wMapSignRoutineIdx
    ld [hl], 0          ; start state machine at step 0
    ret
.cancel
    ld hl, wMapSignRoutineIdx
    ld [hl], $80        ; high bit set = cancelled
    ret
```

Full warps do *not* queue the sign — only connection transitions. The reasoning is aesthetic: a black-screen warp already establishes that you have moved somewhere new; the sign would be redundant. A seamless scroll, by contrast, needs the explicit geography note.

### The State Machine

`RunLandmarkSignAnim` is called every frame from `HandleMapBackgroundEvents`. It drives a six-step state machine indexed by `wMapSignRoutineIdx`:

```asm
.Jumptable:
    dw .Test        ; 0 — same landmark as last time? skip everything
    dw .SlideOut    ; 1 — slide out any previous sign
    dw .Draw        ; 2 — render sign text into VRAM
    dw .SlideIn     ; 3 — slide the sign onto the screen
    dw .Countdown   ; 4 — hold for 120 frames
    dw .SlideOut    ; 5 — slide the sign back off
    dw CancelMapSign; 6 — done
```

The `.Test` step compares `wCurrentLandmark` against `wLastLandmark`. If they match, `CancelMapSign` fires immediately — walking back and forth across a route/town border does not trigger repeated signs. Only a new landmark ID lets the machine proceed.

The sign is drawn in the GBC **window layer** — a second background plane positioned by the hardware registers `rWX` and `rWY`. The window layer is independent of the main BG scroll, so the sign can slide over the world without disturbing it. Setting `rWY` to 144 (the screen height in pixels) hides the window offscreen; the `.SlideIn` step decrements `rWY` by 2 each frame until the sign's three rows are fully visible:

```asm
.SlideIn:
    ldh a, [rWY]
    dec a
    dec a
    ldh [rWY], a
    ldh [hWY], a
    cp SCREEN_HEIGHT_PX - (3 * 8)   ; = 144 - 24 = 120
    ret nz
    ld a, 120
    ld [wMapSignTimer], a
    jp .Next                ; advance to Countdown
```

The `.Countdown` step decrements `wMapSignTimer` once per frame; when it hits zero, `.SlideOut` runs in reverse, incrementing `rWY` by 2 per frame until the sign is off-screen again.

The location name is rendered into VRAM by the `.Draw` step, using the variable-width font renderer (`predef PlaceVWFString`) with centering arithmetic to position the name within the sign's tile area. The landmark ID in `wCurrentLandmark` comes from byte 5 of the primary map header.

---

## 7.8 A Frame in the Life of the Overworld Loop

All of the above systems interact through a single driver: `HandleMap` in `engine/events.asm`. Every frame, after VBlank has run the sprite DMA and audio tick, the overworld loop executes this sequence:

```asm
HandleMap:
    call ResetOverworldDelay
    call HandleMapTimeAndJoypad    ; (1) time + joypad
    call HandleCmdQueue            ; (2) deferred command queue
    call MapEvents                 ; (3) player events (scripts, input, collision)
    ; ...
    call DoBackgroundEvents
    call DoBackgroundEvents

DoBackgroundEvents:
    call HandleOverworldObjects    ; (4) NPC step + player step
    call UpdateStableRNGSeeds
    call NextOverworldFrame        ; (5) frame pacing
    call HandleMapBackgroundEvents ; (6) sprites + landmark sign + camera scroll
    jp EnableEventsIfPlayerNotMoving
```

Walking through each call:

**1. `HandleMapTimeAndJoypad`** — calls `UpdateTime` (advances the RTC, checks for time boundary crossings that should trigger palette fades) and `GetJoypad` (polls hardware, updates `wJoyPressed`/`wJoyHeld`). Also calls `TimeOfDayPals`, which fades the palette registers if a time boundary has just been crossed. This happens in the overworld loop proper, not during map loading — the world re-lights itself while you stand still.

**2. `HandleCmdQueue`** — processes any deferred script command queue entries. Some script commands schedule effects for a later frame.

**3. `MapEvents`** — the main player event dispatcher:

```asm
MapEvents:
    ld a, [wMapEventStatus]
    and a
    ret nz          ; events disabled (mid-step, etc.)
    call PlayerEvents
    call DisableEvents
    jpba ScriptEvents
```

`PlayerEvents` runs in priority order: trainer battle detection, tile events (warp/connection/XY trigger/encounter), map triggers, time events, then player input and movement. The first one that triggers returns carry and sets `wScriptRunning`. Then `ScriptEvents` (the VM dispatcher from §7.2) executes one iteration of any running script and returns — the overworld loop does not spin-wait on scripts; it yields one step per frame, which is how multi-frame script sequences (dialogue boxes, NPC movement) work without blocking.

**4. `HandleOverworldObjects`** — calls `HandleNPCStep` (banked call to `engine/map_objects.asm`; advances each NPC's movement state one step), `_HandlePlayerStep` (advances the player's 8-frame walking animation), and `_CheckObjectEnteringVisibleRange` (spawns NPC sprites when they scroll into view).

**5. `NextOverworldFrame`** — manages frame pacing via `wOverworldDelay`. The overworld normally runs at a 2-frame cadence rather than every VBlank to keep the NPC-step cadence consistent.

**6. `HandleMapBackgroundEvents`** — calls `_UpdateSprites` (builds the OAM shadow buffer for all visible sprites), `RunLandmarkSignAnim` (advances the sign state machine one step), and `ScrollScreen` (commits queued BG tile row/column writes and updates `rSCX`/`rSCY`).

**VBlank ISR** — outside this loop, running at the hardware interrupt: copies the OAM shadow to actual OAM via DMA, flushes any queued BG tile map writes (the row/column from `UpdateBGMapRow`/`UpdateBGMapColumn`), and applies queued palette register values.

The whole cycle runs at around 60 frames per second on hardware. No single piece is large: each function does one named thing and returns. The overworld feels smooth not because any individual component is fast, but because the design refuses to let any of them be slow.

---

## 7.9 Reference: Key Files and Symbols

| File | Contents |
|------|----------|
| `engine/events.asm` | `OverworldLoop`, `HandleMap`, `MapEvents`, `PlayerEvents`, `CheckTileEvent`, `RandomEncounter`, `DoMapTrigger`, `HandleMapTimeAndJoypad`, `HandleOverworldObjects`, `HandleMapBackgroundEvents` |
| `engine/scripting.asm` | `ScriptEvents`, `RunScriptCommand`, `ScriptCommandTable`, all `Script_*` command implementations |
| `home/scripting.asm` | `QueueScript`, `FarQueueScript`, `Script_getnthstring`, `CopyName1`/`CopyName2` |
| `engine/map_triggers.asm` | `MapTriggers` table (`trigger_def` entries, `db -1` terminator) |
| `engine/tile_events.asm` | `CheckWarpCollision`, `CheckDirectionalWarp`, `CheckWarpFacingDown`, `CheckGrassCollision` |
| `engine/warp_connection.asm` | `RunCallback_05_03`, `EnterMapConnection`, directional connection entry functions |
| `home/map.asm` | `GetDestinationWarpNumber`, `CopyWarpData`, `RunMapCallback`, `FillMapConnections`, `RunCurrentMapXYTriggers`, `UpdateBGMapRow`, `UpdateBGMapColumn` |
| `engine/wildmons.asm` | `LoadWildMonData`, `LoadWildMonData_KeepFlutes`, `GrassPointerTable`, `WaterPointerTable` |
| `engine/landmarksigns.asm` | `QueueLandmarkSignAnim`, `RunLandmarkSignAnim`, six-step state machine |
| `macros/map.asm` | `warp_def`, `person_event`, `signpost`, `xy_trigger`, `connection`, `map_header`, `map_header_2` |
| `macros/event.asm` | `sif`, `sendif`, `selse`, and all higher-level scripting macros |
| `constants/map_setup_constants.asm` | `MAPSETUP_*` entry method constants, `MAPCALLBACK_*` callback type constants |
| `constants/map_constants.asm` | `PERSONTYPE_*` constants |

---

## Where to Next

You now understand how the overworld transforms static data into an interactive world — how triggers fire, how the VM interprets scripts, how warps resolve, how connections scroll seamlessly, how NPCs tick, and how the encounter system fires on every blade of tall grass. But this chapter described those systems mostly at rest — as rules and data structures. It said little about the sixty-hertz loop that actually drives them: how the camera glides a pixel at a time across a tile map too small to hold the world, how a single step becomes frames of animation, how a trainer's gaze is computed, how an A-press fans out, and how field moves reshape the map. That clock — the overworld *in motion* — is the subject of Chapter 8. The battle engine that `Script_startbattle` hands control to then follows in Chapter 9.
