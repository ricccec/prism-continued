---
title: "The Living Map — A Deep Read on Pokémon Prism's Overworld"
subtitle: "Tiles, scripts, palettes, and the machine that stitches them together"
---

# The Living Map

*A deep read on how Pokémon Prism's overworld maps work — from raw bytes in ROM to the world you walk through.*

---

## A brief note before we begin

Pokémon games look deceptively simple on screen. A flat grid of coloured pixels. A small character that walks around. Some text boxes. But the moment you start pulling at the source code, you discover that "a map you can walk through" is actually a stack of interlocking systems: data tables, bytecode interpreters, palette rotations keyed to a real-time clock, a camera that buffers three maps simultaneously, a scripting VM that animates NPCs and triggers story events. Each system is compact and clever in its own right. Together, they produce something that feels alive.

This document is a tour of that stack. We'll start with the top — what a map header looks like, and how the game finds it — and work down through tilesets, palettes, map loading, the scripting engine, and finally how the camera maintains the illusion of a seamless connected world. We'll read real code from the codebase along the way, enough that the details are grounded rather than abstract.

Pour something warm. Let's go.

---

## Part One — What is a map, really?

A Pokémon map is not one thing. It is at least four distinct data structures that happen to share a name:

1. **The block grid** — a flat array of block IDs, one byte per position, telling the game which visual tile goes where. This is what a `.blk` file contains.
2. **The map header** — a small metadata record pointing to the tileset, the block data bank, the script header, the event header, and a few gameplay parameters. This is how the engine finds everything else.
3. **The map script header** — triggers and callbacks that run when the map loads or on certain conditions. This is where story events and fly-point registration live.
4. **The map event header** — the list of warps, coord events, signs, and NPCs. This is how the engine knows that stepping on tile (12, 7) should teleport you somewhere, or that the sprite at (4, 10) is a Trainer who battles you.

The first two are pure data. The second two are code mixed with data — bytecode programs that the game's scripting VM reads and executes. A map file (the `.asm` file you'd find under `maps/`) contains the script header and event header. The block grid lives separately, in a compressed binary file that the linker places in a block-data bank. The map header lives in a dedicated section, `maps/map_headers.asm`, along with `maps/second_map_headers.asm`.

When the game boots and you continue a save, it knows two numbers: your map group and your map number. Group and number together uniquely identify the current map. Everything else has to be looked up.

---

## Part Two — The map header: the engine's address book

Every map starts as a two-level header lookup. The primary reason the lookup has two levels is ROM banking: any given map's code might live in a different bank from another map's code, and the bank has to be found before anything else can be read.

The lookup starts at `MapGroupPointers`, a table of `dw` (two-byte pointer) entries, one per map group. There are 58 groups in Prism. Once you have the group pointer, you index into the group's array of primary headers at nine bytes per entry.

```asm
; home/map.asm — GetAnyMapHeaderPointer (simplified)
GetAnyMapHeaderPointer::
    dec b           ; groups are 1-indexed in the data
    ld c, b
    ld b, 0
    ld hl, MapGroupPointers
    add hl, bc      ; each pointer is 2 bytes
    add hl, bc

    ld a, [hli]
    ld h, [hl]
    ld l, a         ; hl now points to this group's first header

    dec c           ; map number is also 1-indexed
    ld b, 0
    ld a, 9
    rst AddNTimes   ; step forward 9 bytes × (map number)
    ret             ; hl → the primary header
```

The `rst AddNTimes` at the bottom is one of those little Game Boy assembly elegances: the `rst` (restart vector) instruction is a one-byte call to a fixed address, and the codebase implements a handful of these as ultra-compact utility calls. `AddNTimes` multiplies `a` by `bc` and adds to `hl` — it is used constantly throughout the map code because almost everything is a fixed-size array of records.

The primary header is nine bytes:

```
byte 0:   bank of the secondary header
bytes 1:  tileset ID
byte 2:   permission (encodes indoor/outdoor/cave/dungeon + palette table selection)
bytes 3–4: pointer to secondary header
byte 5:   landmark ID (for the town map)
byte 6:   music ID
byte 7:   high nibble = phone service flags, low nibble = time-of-day override
byte 8:   fishing group
```

From that nine-byte record, the engine already knows the tileset (and therefore what tilesheet to load), the map's "permission" (which governs both movement rules and which palette color table to use), the music track, and the fishing encounters. Almost every piece of information the overworld needs is derivable from the primary header.

The secondary header is reached by loading the bank from byte 0, switching to it, and following the pointer at bytes 3–4. In the source it is declared by the `map_header_2` macro:

```asm
MACRO map_header_2
; label, map, border block, connections
\1_SecondMapHeader::
    db \3               ; border block ID
    db \2_HEIGHT        ; height in blocks
    db \2_WIDTH         ; width in blocks
    dba \1_BlockData    ; bank + address of block grid (3 bytes)
    dba \1_MapScriptHeader
    dw \1_MapEventHeader
    db \4               ; connection bitmask (NORTH | SOUTH | EAST | WEST)
ENDM
```

The `dba` macro emits three bytes: the bank, the low byte of the address, and the high byte. Together these three bytes tell the engine exactly where to find the block data, the script header, and the event header — even though all three might live in different ROM banks.

The connection bitmask at the end is a bitfield: if bit 3 is set, this map has a north connection; bit 2 is south; bit 1 is west; bit 0 is east. The actual connection data immediately follows in the second map headers file, declared with the `connection` macro:

```asm
map_header_2 CaperRidge, CAPER_RIDGE, 53, NORTH | EAST
connection north, ROUTE_70, Route70, 5, 0, 10, CAPER_RIDGE
connection east,  ROUTE_71_WEST, Route71West, 0, 0, 9, CAPER_RIDGE
```

This tells you everything about CaperRidge's neighbors: it connects to the north with Route 70, and to the east with Route 71 West. Each connection record encodes not just which map is adjacent but where exactly the "strip" of the neighboring map lines up — so that when you walk off the north edge of Caper Ridge, the map to the north is already visible in the buffer and scrolls smoothly into view. We'll come back to the strip in the camera section.

---

## Part Three — The block grid: drawing a world out of bytes

The visual layout of a map is stored in a block grid. Each element of the grid is a single byte — a block ID, 0 to 255. Each block ID corresponds to a 4×4 arrangement of 8×8-pixel tiles, so one block is 32×32 pixels. A map that is 10 blocks wide and 8 blocks high is 320×256 pixels on screen — large enough to fill several Game Boy screens.

Block grids are stored LZ-compressed in one of the map-block-data banks (`$20` through `$35`). The compressed file is named something like `CaperRidge.blk` or `AcaniaDocks.blk`; after build preprocessing it becomes a `.lz` file. At runtime, `LoadBlockData` decompresses it into a WRAM region called `wOverworldMap`:

```asm
; home/map.asm — ChangeMap (simplified)
ChangeMap::
    ld a, [wMapBlockDataBank]
    ld b, a
    ld hl, wMapBlockDataPointer
    ld a, [hli]
    ld h, [hl]
    ld l, a            ; hl = ROM pointer to compressed block data
    ld a, [wMapWidth]
    ld d, a            ; width in blocks
    ld a, [wMapHeight]
    ld e, a

    call FarDecompressAtB_D000
    ; decompressed data lands at wDecompressScratch in WRAM bank 6

    ; then copy from scratch into wOverworldMap,
    ; leaving a 3-block border on all sides for neighboring maps
    ld hl, wOverworldMap
    ; ... offset by 3 rows + 3 columns, then copy row by row
```

The "3-block border" is important and we'll see it again. `wOverworldMap` is not just the current map's block data. It is a larger buffer that includes three blocks of each neighboring map's data on each side, so the camera can show adjacent terrain while the player is near an edge. The current map's blocks land in the middle of that buffer; the surrounding strips are filled in separately by `FillMapConnections`.

The conversion from block ID to pixels happens through three tileset files. It is a two-step indirection that deserves a slow read.

---

## Part Four — Tilesets: the three tables

Every map has a tileset ID. The tileset tells the engine which set of three binary files to load:

- `tilesets/XX_metatiles.bin` — maps each block ID to 16 tile IDs (a 4×4 grid)
- `tilesets/XX_attributes.bin` — maps each block ID to 16 palette-slot indices (a parallel 4×4 grid)
- `tilesets/XX_collision.asm` — maps each block ID to 4 collision bytes (one per 2×2 quadrant)

These files are loaded into WRAM during map setup:

```asm
; home/map.asm — LoadMetatilesTilecoll
LoadMetatilesTilecoll:
    ld hl, wTilesetBlocksBank
    ld de, wDecompressedMetatiles   ; 256 × 16 bytes
    call .Decompress

    ld hl, wTilesetAttributesBank
    ld de, wDecompressedAttributes  ; 256 × 16 bytes
    call .Decompress

    ld hl, wTilesetCollisionBank
    ld de, wDecompressedCollision   ; 256 × 4 bytes
    call .Decompress
```

Consider block ID 3 in tileset 0 (the outdoor/Johto tileset). To render it:

1. Look up bytes 48–63 in `wDecompressedMetatiles` (block 3 × 16 bytes). These are 16 tile IDs, arranged in a 4×4 grid, read left-to-right then top-to-bottom.
2. Look up bytes 48–63 in `wDecompressedAttributes`. These are 16 numbers in the range 0–7, each one the CGB background palette slot for the corresponding tile.
3. For each tile ID, look up 16 bytes in the tileset's tile graphics data (loaded into VRAM). Each set of 16 bytes is one 8×8 tile in Game Boy 2bpp format.
4. Render the four colours of each tile from the palette slot (see Part Five).

That path — block ID → tile IDs → pixel data, with a parallel path of block ID → palette slots → colour values — is the entire rendering pipeline, at its core. The metatile system (blocks containing tiles) exists because a 32×32-pixel "block" is more economical to describe than 16 individual 8×8 tiles when the same combinations repeat constantly (grass corners, road segments, fence sections).

The collision file works the same way, but simpler: four bytes per block, one per 2×2-tile quadrant, each byte a collision type from a small set of constants:

```asm
; tilesets/00_collision.asm (excerpt)
    tilecoll WALL,      WALL,      WALL,      WALL       ; block 0 — impassable
    tilecoll FLOOR,     FLOOR,     FLOOR,     FLOOR      ; block 1 — passable
    tilecoll FLOOR,     FLOOR,     FLOOR,     FLOOR      ; block 2 — passable
    tilecoll TALL_GRASS,TALL_GRASS,TALL_GRASS,TALL_GRASS ; block 3 — encounter
    tilecoll FLOOR,     FLOOR,     FLOOR,     FLOOR      ; block 4 — passable
    tilecoll WALL,      WALL,      WALL,      WALL       ; block 5 — impassable
    ; ...
    tilecoll WATERFALL, WATERFALL, WATER,     WATER      ; waterfall tile
```

When `GetCoordTile` needs the collision type at a map coordinate, it does three lookups: map coordinates → block ID (from `wOverworldMap`), block ID → 4-byte collision entry (from `wDecompressedCollision`), then picks the correct quadrant byte based on whether the coordinate falls in the top/bottom half and left/right half of the block. The result is a single collision byte: `WALL`, `FLOOR`, `TALL_GRASS`, `WATER`, `DOOR`, `CAVE`, `LEDGE_DOWN`, `ICE`, and so on. The movement engine and tile event system read this byte to decide what to do.

One collision constant deserves special mention: `COLL_HIGH_NYBBLE_WARPS`. When the collision byte's upper nibble matches that value, the game treats the tile as a warp trigger regardless of what the lower nibble says. This is how doorways and cave entrances work — the tileset author marks certain blocks with the warp collision value, and the tile event system picks them up automatically. No per-map configuration needed.

---

## Part Five — Colour and light: the palette system

The Game Boy Color supports eight background palettes active simultaneously. Each palette is four colours. A tile can reference any of the eight, and within the palette it draws pixel values 0, 1, 2, or 3 mapping to the four colours. The `attributes` table (from the tileset) assigns one of the eight palette slots to each tile in a block. The actual RGBA values in those slots are loaded by the palette system.

The palette system has two inputs from the map header: the **permission** byte and the **time of day**. Together they determine which set of eight four-colour palettes gets loaded for a given map.

**Permission** encodes the environment type:

| Value | Constant | Environment |
|-------|----------|-------------|
| 0 | — | Outdoor |
| 1 | TOWN | Outdoor |
| 2 | ROUTE | Outdoor |
| 3 | INDOOR | Indoor |
| 4 | CAVE | Cave/dungeon |
| 5 | PERM_5 | Cave/dungeon |
| 6 | GATE | Indoor (gate building) |
| 7 | DUNGEON | Cave/dungeon |

Each environment class uses a different color table: `OutdoorColors`, `IndoorColors`, or `DungeonColors`. Each color table is a 4×8 array — four rows for the four time-of-day slots, eight entries per row. Each entry is an index into a master palette table called `TilesetBGPalette`.

The palette loading code in `engine/color.asm` does this lookup in two tight loops:

```asm
; engine/color.asm — LoadMapPals (core loop, simplified)
LoadMapPals:
    call LoadSpecialMapPalette
    jr c, .got_pals      ; some tilsets override everything

    ld a, [wPermission]
    and 7
    ; index into TilesetColorsPointers to get OutdoorColors / IndoorColors / DungeonColors
    ld hl, .TilesetColorsPointers
    add hl, de           ; de = 2 * (permission & 7)
    ld a, [wTimeOfDayPal]
    and 3                ; 0=morn, 1=day, 2=nite, 3=dark
    ; multiply by 8 (8 palette slots per row), add to base
    add a \ add a \ add a
    add l \ ld l, a
    adc h \ sub l \ ld h, a
    ; hl now points to 8 palette-index bytes for this environment+time-of-day

    ld b, 8              ; 8 background palettes to fill
.outer_loop:
    ld a, [de]           ; palette index → TilesetBGPalette
    inc de
    ; index into TilesetBGPalette (8 bytes per palette entry)
    ld l, a \ ld h, 0
    add hl, hl \ add hl, hl \ add hl, hl
    ld de, TilesetBGPalette
    add hl, de
    ld c, 8              ; 8 bytes = 4 RGB555 colours
.inner_loop:
    ld a, [de] \ inc de
    ld [hli], a          ; store into wOriginalBGPals
    dec c
    jr nz, .inner_loop
    dec b
    jr nz, .outer_loop
```

The practical result: a cave map at night uses a much darker, more muted palette than a route in daytime, without the map file itself needing to specify any colours. The map says "I am type CAVE" and the palette system fills in the rest.

**Time of day** itself is read from the real-time clock and processed into four slots — morning, day, night, and the special "dark cave" mode. The RTC gives raw hours and minutes; `UpdateTime` in `engine/time.asm` maps those to the three normal slots based on configurable hour boundaries. The "dark cave" slot is special: it is activated by a bit in `wMapTimeOfDay` and used for caves that require Flash to illuminate. In that mode the palette logic checks whether Flash has been used:

```asm
; engine/timeofdaypals.asm — ReplaceTimeOfDayPals
.DarkCave:
    ld a, [wStatusFlags2]
    bit 0, a             ; has Flash been used?
    jr nz, .UsedFlash
    ld a, %11111111      ; fully dark: all 4 palette slots = brightness level 3
    ld [wTimeOfDayPalset], a
    ret

.UsedFlash:
    ld a, %10101010      ; partially lit: all 4 slots = brightness level 2
    ld [wTimeOfDayPalset], a
    ret
```

The `wTimeOfDayPalset` byte is a packed bitfield: two bits per slot, four slots, encoding a "brightness level" from 0 (full bright) to 3 (darkest). The four extractors in `GetTimePalette` unpack the appropriate two bits depending on which time slot we're in:

```asm
GetTimePalette:
    ld a, [wTimeOfDay]
    jumptable
.TimePalettes:
    dw .MorningPalette
    dw .DayPalette
    dw .NitePalette
    dw .DarknessPalette

.DayPalette:
    ld a, [wTimeOfDayPalset]
    and %00001100       ; bits 2–3
    srl a
    srl a               ; shift down to 0–3
    ret
```

The `.BrightnessLevels` table near `ReplaceTimeOfDayPals` determines the default `wTimeOfDayPalset` for each map permission type. For a normal outdoor map, morning uses brightness level 3-2-1-0 (morning being brightest for the first slot, slightly dimmed for later slots), day uses all level 1 (uniform midday brightness), and night uses 2-2-2-2.

The final detail in the palette system is that it changes at runtime when the clock ticks past a time boundary. The function `_TimeOfDayPals`, called periodically from the overworld loop, checks whether `wTimeOfDay` has changed since the last frame. If it has, it smoothly fades the palettes by stepping through `GetTimePalFade`:

```asm
.cgbfade
    db %11111111, %11111111, %11111111   ; fully lit
    db %11111110, %11111110, %11111110
    db %11111001, %11111001, %11111001
    ; ... (7 steps total)
    db %00000000, %00000000, %00000000   ; fully dark
```

Each row is three bytes — one for BG palettes, one for OBJ palettes — and the animation marches through them with a two-frame delay between steps. The transition from midday blue sky to evening purple is not a hard cut; it is a seven-step fade that the player probably notices but couldn't name.

And for a handful of special maps — the Espo Forest, Olcan Isle, the Trainer House Battle Room, the Tunod area — none of the above applies. These maps declare `TILESET_ESPO_FOREST` or similar, and `LoadSpecialMapPalette` detects them and loads a bespoke `.pal` file instead. Those files are the same format as `bg.pal` but tuned for the specific aesthetic of that area. The system is escapable when you need it to be.

There is one more palette layer that sits below all of this and is easy to miss: `LoadMapPals` finishes by reading `tilesets/roof.pal` at offset `wMapGroup * 8` and overwriting BG palette 6, colors 1–2. Each map group has exactly four `RGB` entries in that file — two for day, two for night. Because the lookup key is the **map group number**, all maps in the same group share this roof color. Moving a map to a different group changes that color, even if its `map_header` palette field is unchanged. See [`map-rendering.md`](map-rendering.md) §4 for the exact byte layout.

---

## Part Six — The setup sequence: loading a map is a program

Now you know what a map is. The question is how it gets loaded. The answer is a small bytecode program called a *map setup script*.

When the engine decides it is time to enter a new map — because the player walked through a door, exited a cave, flew to a city, or continued a saved game — it sets a byte in `hMapEntryMethod` describing *how* the transition happened. That byte indexes into a jump table of map setup scripts, one per entry method:

```asm
; engine/map_setup.asm
MapSetupScripts:
    dw MapSetupScript_Warp        ; F1 — walked through a warp tile
    dw MapSetupScript_Continue    ; F2 — loaded from a save
    dw MapSetupScript_ReloadMap   ; F3 — reloaded in-place (after a menu)
    dw MapSetupScript_Teleport    ; F4 — Escape Rope / teleport
    dw MapSetupScript_Door        ; F5 — walked through a door
    dw MapSetupScript_Fall        ; F6 — fell through a hole
    dw MapSetupScript_Connection  ; F7 — walked into a neighboring map
    dw MapSetupScript_LinkReturn  ; F8 — returned from link trade/battle
    dw MapSetupScript_Train       ; F9 — exited the Magnet Train
    dw MapSetupScript_Submenu     ; FA — returned from a menu
    dw MapSetupScript_BadWarp     ; FB — fallback for undefined warps
    dw MapSetupScript_Fly         ; FC — used Fly
    dw MapSetupScript_BattleTower ; FD — Battle Tower entry
```

Each entry is a sequence of `mapsetup` commands, executed one after another. The full warp sequence (the common case for walking through a door or cave entrance) is:

```asm
MapSetupScript_Warp:
    mapsetup DisableLCD
    mapsetup MapSetup_Sound_Off
    mapsetup LoadSpawnPoint
    mapsetup LoadMapAttributes    ; parse headers, read warps, NPCs, scripts
    mapsetup RunCallback_05_03    ; run new-map callback, reset script state
    mapsetup SpawnPlayer
    mapsetup RefreshPlayerCoords
    mapsetup GetCoordOfUpperLeftCorner
    mapsetup LoadBlockData        ; decompress block grid into wOverworldMap
    mapsetup BufferScreen         ; copy visible 6×5 blocks into wScreenSave
    mapsetup LoadGraphics         ; load tileset tile data into VRAM
    mapsetup LoadMetatilesTilecoll ; decompress metatile/attr/collision tables
    mapsetup LoadMapTimeOfDay     ; read time-of-day from map header
    mapsetup LoadObjectsRunCallback_02  ; spawn NPCs
    mapsetup LoadMapPalettes      ; compute and apply the 8 BG palettes
    mapsetup ForceUpdateCGBPalsIfMapSetupWarp
    mapsetup EnableLCD
    mapsetup SpawnInFacingDown
    mapsetup RefreshMapSprites
    mapsetup PlayMapMusic
    mapsetup FadeInMusic
    mapsetup FadeInPalettes
    mapsetup ActivateMapAnims
    mapsetup LoadWildMonData
    mapsetup_end
```

That is the entire loading sequence for a normal warp — every step named, ordered with purpose. Notice that `DisableLCD` comes first, before any VRAM writes, because writing to VRAM while the LCD is drawing produces graphical corruption. `EnableLCD` comes back at step 16, after all the VRAM writes are done and the palettes have been loaded into the hardware registers. The `FadeInPalettes` at the end uses the animated fade routine to bring the screen up from black.

The connection case (`MapSetupScript_Connection`) is deliberately lighter. It runs when you walk into an adjacent map by scrolling:

```asm
MapSetupScript_Connection:
    mapsetup SuspendMapAnims
    mapsetup EnterMapConnection   ; update wMapGroup, wMapNumber, anchor pointer
    mapsetup LoadMapAttributes
    mapsetup RunCallback_05_03
    mapsetup RefreshPlayerCoords
    mapsetup LoadBlockData
    mapsetup LoadTilesetHeader    ; only reload the tileset header, not the full GFX
    mapsetup SaveScreen           ; copy the visible portion that will be reused
    mapsetup LoadObjectsRunCallback_02
    mapsetup FadeToMapMusic
    mapsetup LoadMapPalettes
    mapsetup QueueLandmarkSignAnim
    mapsetup _UpdateTimePals
    mapsetup LoadWildMonData
    mapsetup UpdateRoamMons
    mapsetup ActivateMapAnims
    mapsetup_end
```

There is no `DisableLCD` here, no full VRAM reload, no screen fade. The adjacent map was already partially loaded into `wOverworldMap` (the 3-block border strips), so only the header metadata, the palette, the NPCs, and the music need updating. The transition is instant because the preparation was done in advance.

The interpreter that reads these scripts is a simple loop in `engine/map_setup.asm`:

```asm
ReadMapSetupScript:
    ld a, [hli]      ; read next command byte
    cp -1            ; -1 is the terminator (mapsetup_end)
    jr nz, .run
    ret

.run:
    ld c, a
    ld b, 0
    ld hl, MapSetupCommands
    add hl, bc       ; each entry is 3 bytes (bank + address)
    add hl, bc
    add hl, bc
    call FarPointerCall   ; call the function in the right bank
    ; loop back to read next byte
```

Every `mapsetup` is one byte in the script. `mapsetup_end` is the byte `$ff`. The commands themselves are named functions scattered across `engine/map_setup.asm`, `home/map.asm`, and elsewhere. The table `MapSetupCommands` maps each byte value to its three-byte far pointer (bank + 16-bit address). There are 48 distinct commands, from `EnableLCD` (00) through `LoadMetatilesTilecoll` (30) at the end.

The design means that adding a new kind of map transition requires writing one new script (a sequence of `mapsetup` calls), and any of the 48 existing building blocks can be reused in any order. The Battle Tower gets its own script that fades the old music rather than cutting it; the Magnet Train skip reloads warps before placing the player. Each transition is tailored, but built from the same alphabet of atomic operations.

---

## Part Seven — Map scripts: the small programs in every room

Every map has a script header. In the source it looks like this (from `AzaleaTown.asm`):

```asm
AzaleaTown_MapScriptHeader:
    db 0    ; trigger count
    db 1    ; callback count

    dbw MAPCALLBACK_NEWMAP, .set_fly_flag

.set_fly_flag:
    setflag ENGINE_FLYPOINT_AZALEA_TOWN
    return
```

This is as small as a map script can get: no triggers, one callback, and the callback just sets a single engine flag so Fly works for this city. But the format scales: the trigger count and callback count can be as large as needed, and each one is a pointer to a bytecode script program.

The distinction between *triggers* and *callbacks* is important.

A **callback** is associated with a callback type — `MAPCALLBACK_NEWMAP` fires when the map is first entered; `MAPCALLBACK_TILES` fires during block data loading (useful for maps with dynamic tiles); `CB2_OVERWORLD` fires every frame while in the overworld; `MAPCALLBACK_OBJECTS` fires when NPCs are spawned. Each callback type is a single byte. The engine iterates the callback list and finds the first entry whose type matches what it's currently executing.

A **trigger** is a one-shot event tied to a game condition. The trigger table in `engine/map_triggers.asm` lists every map that has trigger-driven behavior — the Pokécenter back room, the Trade Center, the Battle Tower, Route 69, various puzzle rooms — and associates each with a WRAM pointer to the trigger state. When you enter one of these maps, the trigger system checks the WRAM pointer to see if the trigger should fire and if so, runs a script. Triggers are how the game implements complex entry sequences like the Route 69 southern gate check.

The scripts themselves are executed by the VM in `home/scripting.asm` (the dispatcher) and `engine/scripting.asm` (the command implementations). There are over a hundred script commands. Here is a representative slice:

```asm
ScriptCommandTable:
    dw Script_scall           ; 0 — call sub-script
    dw Script_farscall        ; 1 — call sub-script in another bank
    dw Script_ptcall          ; 2 — call via predef table
    dw Script_jump            ; 3 — unconditional jump
    dw Script_farjump         ; 4 — jump into another bank
    dw Script_if_equal        ; 6 — branch if var == value
    dw Script_if_not_equal    ; 7
    dw Script_iffalse         ; 8 — branch if last check was false
    dw Script_iftrue          ; 9 — branch if last check was true
    dw Script_special         ; call a numbered special function
    dw Script_giveitem        ; 1f — add item to bag
    dw Script_takeitem        ; 20 — remove item from bag
    dw Script_checkitem       ; 21 — check bag for item, set flag
    dw Script_givemoney
    dw Script_takemoney
    dw Script_checkflag       ; check event flag, set condition
    dw Script_setflag         ; set event flag
    dw Script_clearflag       ; clear event flag
    ; ...
```

Each command byte occupies one byte in the ROM. Operands follow: a flag index is two bytes, an item + quantity is two bytes, a pointer is two bytes (relative to the current script bank). The VM's main loop reads one byte, dispatches through the table, and the command function advances the `wScriptPos` pointer by however many operand bytes it consumed. The result is a variable-width bytecode format with the feel of a domain-specific language and the size efficiency of raw binary.

Here is a real script from `AcaniaDocks.asm`, lightly annotated:

```asm
AcaniaDocksNPC4:
    faceplayer              ; NPC turns to face you
    checkevent EVENT_ACANIA_TM_44   ; is the TM already given?
    sif false, then         ; if NOT given:
        opentext
        writetext .giveTM
        givetm TM_REST + RECEIVED_TM  ; give the TM
        setevent EVENT_ACANIA_TM_44   ; record that it's been given
    sendif
    jumptext .describeTM    ; either way, show the TM description

.giveTM:
    ctxt "The calm sea is"
    ; ... (dialogue text)
    sdone

.describeTM:
    ctxt "TM44 is Rest."
    ; ...
    done
```

The `sif`/`sendif` pair is a higher-level scripting macro that compiles down to `iffalse`/`jump` pairs. The underlying bytecode has no structured control flow — it is flat jumps — but the macro layer gives it a legible, almost procedural feel.

Reading a map script and imagining what the player experiences is one of the nicer affordances of this codebase. The script says what happens; the code says how. Both layers are readable in the same file.

---

## Part Eight — Warps: the portals

Every door, every cave entrance, every building exit is a warp. In the map event header, warps are declared with `warp_def`:

```asm
AcaniaDocks_MapEventHeader:: db 0, 0

.Warps:
    db 8                                          ; warp count
    warp_def 15, 7, 1, ACANIA_POKECENTER         ; (y, x, dest_warp_index, dest_map)
    warp_def  9, 3, 1, ACANIA_MART
    warp_def 19, 7, 1, ROUTE_81_NORTHGATE
    warp_def 19, 8, 2, ROUTE_81_NORTHGATE
    warp_def  9, 16, 1, ACANIA_GYM
    warp_def  5, 28, 1, ACANIA_LIGHTHOUSE_F1
    warp_def 15, 13, 1, ACANIA_HOUSE
    warp_def 11, 23, 1, ACANIA_TM63
```

Each `warp_def` compiles to five bytes: Y, X, destination warp index, destination map group, destination map number. The destination warp index is the key: it refers to a numbered entry in the destination map's *own* warp list. So "take warp 1 of ACANIA_POKECENTER" means "land at the coordinates declared by warp_def #1 in the Pokécenter's `.Warps` section."

This pairing convention means every warp exists in two places: the *exit* warp defines which tile you leave from and where you go; the *entry* warp (on the other side) defines which tile you land on. They reference each other by index. Add a new door? Add a warp on each side. Change which tile a door lands on? Update the entry warp's coordinates in the destination map.

The engine discovers a warp when the player stands on a tile with a warp collision type. `CheckWarpCollision` checks whether `wPlayerStandingTile` matches `COLL_HIGH_NYBBLE_WARPS` or a few specific values, then returns carry if it's a warp. `GetDestinationWarpNumber` walks the warp header (loaded into WRAM as `wCurrMapWarpHeaderPointer`) and compares each warp's Y/X against the player's adjusted position:

```asm
GetDestinationWarpNumber:
    ld a, [wPlayerStandingMapY]
    sub 4           ; subtract camera offset
    ld e, a
    ld a, [wPlayerStandingMapX]
    sub 4
    ld d, a
    ld c, [wCurrMapWarpCount]
    ld hl, wCurrMapWarpHeaderPointer

.loop:
    ld a, [hli]     ; Y of this warp entry
    cp e
    jr nz, .next
    ld a, [hli]     ; X of this warp entry
    cp d
    jr z, .found_warp
.next:
    ; advance hl by 5 (warp entry size), decrement count
    ; ...
```

Once found, `CopyWarpData` copies the destination warp index, map group, and map number into the transition variables (`wNextWarp`, `wNextMapGroup`, `wNextMapNumber`), and the map setup sequence takes over.

Some tiles are "directional warps" — the carpet tiles in gyms that trigger only when you step in a specific direction, or the staircase tiles that only activate when you walk into them facing the right way. `CheckDirectionalWarp` checks for these and returns clear carry (not an immediate warp) if the tile is one of them, giving the player movement code a chance to validate direction before activating.

There is a special warp destination index value: `$ff`. When a warp declares `$ff` as its destination index, it means "send the player back to wherever they came from." This is how cave exits work — the cave entrance's warp says `$ff`, so the player reappears at the cave mouth they entered through. The engine stores the previous warp index in `wPrevWarp` before any transition, and `CopyWarpData` restores it when it sees `$ff`.

---

## Part Nine — Connections: the scrolling seam

Walking off the edge of a route into a town is different from walking through a door. There is no black screen, no fade, no explicit entry animation. The world simply continues. How?

The answer is in the 3-block border we saw in the block grid loading. When you load Caper Ridge, `LoadBlockData` decompresses Caper Ridge's own block data into the middle of `wOverworldMap`. Then `FillMapConnections` is called. It checks the four direction bits of the connection bitmask. For each direction that has a connection, it:

1. Looks up the neighbouring map's block data bank and pointer.
2. Decompresses the neighbour's block grid into a scratch buffer.
3. Copies the three rows (or columns) from the neighbour that are nearest the shared edge into the border of `wOverworldMap`.

So `wOverworldMap` at any given moment is a composite: the current map's blocks in the center, and up to three rows of each adjacent map's blocks forming a border. The camera renders from this buffer. When you walk north, you're actually already seeing the first three blocks of the northern map. The connection data declares exactly which strip of the neighbour aligns with which strip of the current map.

The `connection` macro in `macros/map.asm` is where this alignment is specified:

```asm
; connection <direction>, <neighbor_id>, <neighbor_label>, <edge_offset>, <neighbor_offset>, <strip_length>, <this_map_id>
connection north, ROUTE_70, Route70, 5, 0, 10, CAPER_RIDGE
```

| Argument | Meaning |
|----------|---------|
| `direction` | `north`, `south`, `east`, or `west` |
| `neighbor_id` | Neighbor's map-group constant; provides `GROUP_*`, `MAP_*`, `*_WIDTH`, `*_HEIGHT` |
| `neighbor_label` | Unused (will eventually merge with `neighbor_id`) |
| `edge_offset` | Column (N/S) or row (E/W) along *this* map's edge where the seam starts |
| `neighbor_offset` | Column (N/S) or row (E/W) along the neighbor's opposite edge where the strip begins |
| `strip_length` | How many tiles wide/tall the visible seam window is |
| `this_map_id` | This map's own constant — provides `*_WIDTH`, `*_HEIGHT` |

For the north case the macro emits:

```asm
    dw wDecompressScratch + \2_WIDTH * (\2_HEIGHT - 3) + \5
    ; ^ bottom 3 rows of the neighbor, slid by neighbor_offset
    dw wOverworldMap + \4 + 3
    ; ^ target column in this map's padded buffer (+3 for border)
    db \6        ; strip length
    db \2_WIDTH  ; neighbor's width (row stride)
    ; ... camera-alignment byte: (edge_offset - neighbor_offset) * -2
```

`(edge_offset - neighbor_offset) * -2` is the camera-alignment byte. When the two maps don't share the same x/y origin, this signed offset shifts the camera on transition so motion stays smooth.

When you actually cross the boundary, `EnterMapConnection` in `engine/warp_connection.asm` updates `wMapGroup` and `wMapNumber` to the neighbour's values and adjusts the overworld anchor pointer so the camera now treats the neighbour as the "current" map. The `MapSetupScript_Connection` sequence runs, refreshing the metadata but not the block data (because the blocks are already in `wOverworldMap`).

The camera itself is maintained through a simple double-buffer scheme in VRAM. The Game Boy's background layer is a 32×32 tile grid wrapping at both edges — effectively a torus. The current map's visible tiles are DMA-transferred into a sliding window of that torus each frame. When the player takes a step, one row or one column of new tile IDs is pushed into the BG map via `UpdateBGMapRow` or `UpdateBGMapColumn`, with the data sourced from `wOverworldMap`. The hardware then renders whatever is currently in VRAM, at the scroll offsets stored in the `rSCX`/`rSCY` registers.

The scroll registers are what make motion smooth: between the push of new tile data and the hardware drawing, the scroll registers are offset by up to 8 pixels (one tile width), so the player animation walks through the step rather than jumping. The animation advances one pixel per frame, eight frames per step.

---

## Part Ten — Wild encounters: the randomness beneath the grass

One of the things a map declares in its secondary header is a **fishing group**. One of the things the map setup script runs is `LoadWildMonData`. Both of these relate to the same question: what creatures live here?

Wild encounter data is not stored in the map file directly. It lives in separate tables, one table per game region — Naljo, Rijon, Johto, Kanto, Sevii, Tunod, and a Mystery Zone. Each table is a large list of per-map encounter records. `LoadWildMonData` finds the right record by walking the table for the current map ID.

The data inside each map's encounter record follows the format we saw in `data-formats.md`: three encounter-rate bytes (morning, day, night) followed by the ten grass slots and five water slots. But there's a wrinkle the source format doesn't show: each of those three rates is stored independently in WRAM (`wMornEncounterRate`, `wDayEncounterRate`, `wNiteEncounterRate`). When the wild encounter roll runs each step, it picks the rate for the *current* time slot:

```asm
; engine/wildmons.asm — LoadWildMonData (core)
LoadWildMonData:
    ld a, 1
    ld [wEncounterRateStage], a   ; 1 = normal rate
LoadWildMonData_KeepFlutes:
    call _GrassWildmonLookup       ; find this map's grass record
    jr c, .copy
    ; no grass data for this map — zero all rates
    ld hl, wMornEncounterRate
    xor a
    ld [hli], a   ; morn
    ld [hli], a   ; day
    ld [hl], a    ; nite
    jr .done_copy
.copy:
    ; copy the 3 rate bytes from ROM into WRAM
    inc hl
    inc hl
    ld de, wMornEncounterRate
    ld bc, 3
    rst CopyBytes
.done_copy:
    call _WaterWildmonLookup       ; find water data
    ; ...
    ; apply Repel / Lure flute modifier
    ld a, [wEncounterRateStage]
    and a
    jr z, .halfRate       ; stage 0 = Repel active → halve all rates
    dec a
    ret z                 ; stage 1 = normal → no change
    ; stage 2 = lure → double all rates
    ; ...
```

The `wEncounterRateStage` variable is set by the Repel/Lure system: 0 for Repel (half rate, floored at 1), 1 for normal, 2 for Lure (doubled rate, capped at `$ff`). The rates are applied every time `LoadWildMonData` runs — which is every map load, so using a Repel in one room and walking into another resets it correctly.

The actual encounter roll happens in `engine/player_step.asm`, every step the player takes in tall grass or water:

```asm
; conceptually:
ld a, [wPlayerStandingTile]
; if TALL_GRASS or SUPER_TALL_GRASS or WATER:
    ld a, [wWalkCounter]
    inc [wWalkCounter]
    ; roll RNG against encounter rate
    ; if triggered: select a slot from the ten grass slots
    ;               based on a weighted distribution (fixed weights, not uniform)
    ;               then spawn a wild Pokémon at a level in [level_min, level_max]
```

The slot selection is not uniform across the ten entries. The encounter slot weights in Crystal (inherited here) follow a known distribution: the first few slots appear more often than the last few, creating the characteristic "one or two species dominate, others are rare" feel of a route's encounters. That distribution is baked into a lookup table in the engine, not configurable per map.

The fishing group, stored in the map header's byte 8, selects which of the game's fishing rod tables to use. There are multiple groups, each with different species per rod type (Old Rod, Good Rod, Super Rod). Walking into any indoor map resets the fishing group to zero (no fishing), which is why you can't fish inside a house.

Everything about the encounter system is designed so that the map files are clean and declarative — just rates and species, no logic. The logic lives in the engine. The rates get multiplied or halved by Repel effects at load time. The slot weighting is table-driven in the engine. The time-of-day selection happens at roll time. The same three bytes of encounter data in ROM produce different actual behavior depending on what time it is, what item the player recently used, and whether they're on a bike or surfing.

---

## Part Eleven — Landmark signs: a flicker of geography

When you cross from one named location to another — stepping from Route 70 onto Caper Ridge, or from Route 69 into Heath Village — a small sign slides up from the bottom of the screen, holds for a moment, then slides back down. It names the place you just entered. This is the landmark sign animation, and it is implemented almost entirely in one file: `engine/landmarksigns.asm`.

The system has two parts. The first is a six-step state machine, advanced one step per frame:

1. **Test** — check whether the current landmark is the same as the last displayed one. If so, skip the whole animation.
2. **SlideOut** — if a previous sign is still on screen, slide it off (incrementing the window Y position two pixels per frame until it's below the screen).
3. **Draw** — render the sign graphics and the location name into VRAM.
4. **SlideIn** — slide the sign onto the screen (decrementing the window Y position two pixels per frame until it's three tiles tall).
5. **Countdown** — display the sign for 120 frames (two seconds at 60fps).
6. **SlideOut** — slide it back off.

The sign is drawn in the GBC *window layer* — a second background layer that sits on top of the main background, positioned by the `rWX` / `rWY` hardware registers. The window layer scrolls independently of the main background, which is how the sign can slide in and out while the world behind it remains stationary. Setting `rWY` to 144 (the screen height in pixels) hides the window; decrementing it by 2 each frame slides three rows of sign tiles into view.

The name itself is placed using the variable-width font renderer (`predef PlaceVWFString`), then centered within the sign's tile area. The centering arithmetic in the source is notably dense — it computes the pixel width of the rendered name, divides by the sign's available width, and shifts the tile data left or right to center it — because at the hardware level, "centering text" means shifting actual pixel data within 8-pixel-wide tile slots, not inserting padding. The result is a sign that always looks geometrically centered regardless of how long the location name is.

The landmark ID comes from the primary map header (byte 5). Each map that should display a sign has a non-zero landmark ID; landmarks 1–127 correspond to named locations, and a few special values (`DUMMY2`, `DUMMY4`, `MYSTERY_LANDMARK`) are excluded from triggering the animation. Indoor maps, gates, and maps that are sub-areas of a larger location typically share the same landmark ID — the sign appears when you first enter Heath Village, but not when you step between the Pokécenter and the Gym inside it.

The animation is queued during the connection map setup (`MapSetupScript_Connection` calls `mapsetup QueueLandmarkSignAnim`) but not during full warp transitions. The logic is aesthetic: when you fade to black and come up in a new place, you already know where you are from the context. When you scroll seamlessly from one area to another, the sign is the game's way of telling you the geography has changed.

---

## Part Twelve — NPCs: objects with a heartbeat

A map's NPCs are declared in the `.ObjectEvents` section. Each one is a `person_event`:

```asm
person_event SPRITE_COOLTRAINERF, 12, 8,
    SPRITEMOVEDATA_WALK_LEFT_RIGHT, 0, 0,
    MAPCALLBACK_OBJECTS, PERSONTYPE_NORMAL,
    Route34_Trainer_1, EVENT_ROUTE_34_TRAINER_1
```

The macro is more complex than it looks — it has variable syntax depending on `PERSONTYPE`. For a normal NPC it produces around a dozen bytes: sprite ID, Y, X (each +4 for the camera offset), movement type, palette/function nibbles packed into one byte, and a two-byte pointer to the NPC's script followed by a two-byte event flag. For a trainer it adds additional routing through the trainer-battle system. For a mart worker it encodes a mart type and mart ID instead of a script pointer.

When `LoadObjectsRunCallback_02` runs during map setup, it reads these bytes from the ROM and copies them into a fixed array of object structs in WRAM (`wMap1Object` through `wMap13Object`, 13 objects maximum per map). Each WRAM object struct holds the sprite ID, coordinates, current movement state, and a pointer back to the ROM data for the NPC's script. The event flag check happens at spawn time: if the event flag is non-zero and that flag is set in `wEventFlags`, the NPC is not spawned.

After spawning, NPCs are updated every frame by `engine/map_objects.asm` (the banked version of the NPC tick, called via `farcall`). Movement types like `SPRITEMOVEDATA_WALK_LEFT_RIGHT` produce small movement sequences: the NPC walks right a certain number of tiles, pauses, turns, walks left, pauses, turns again. `SPRITEMOVEDATA_WANDER_AROUND` picks random directions with random delays. `SPRITEMOVEDATA_STATIONARY` never moves but still faces the player when you talk to them. `SPRITEMOVEDATA_FOLLOWER` implements the "following" NPC that tracks the player step for step.

When you interact with an NPC (`A` pressed while facing them), the engine finds the closest NPC in front of the player, locates its script pointer, and calls `CallScript` with the appropriate bank and address. The scripting VM takes over. For trainers, the script is a `trainer` macro that expands into a flag check + battle initiation + pre-battle and post-battle dialogue sequence.

---

## Part Thirteen — Putting it all together: a frame in the life of a map

Let's follow a single frame of the overworld loop, beginning to end.

The main overworld loop lives in `engine/overworld.asm`. Every frame (after VBlank runs the sprite DMA and audio tick):

1. **Joypad** — `home/joypad.asm` polls the hardware and updates `wJoyPressed` and `wJoyHeld`.
2. **Time** — every N frames, `UpdateTimePals` calls `_TimeOfDayPals`, which checks whether the RTC has crossed a time boundary. If so, it fades the palettes to the new time-of-day set. This happens in the overworld loop without any explicit map change.
3. **Map animations** — tile animations (water shimmering, flowers bobbing) are advanced if `hMapAnims` is non-zero. These are hard-coded tile replacements that cycle at a fixed rate.
4. **Script** — if `wScriptRunning` is non-zero, `ScriptEvents` executes one iteration of the current script, then returns. The overworld loop does not advance while a script is executing; it yields control on each frame, which is how scripts that span multiple dialogue boxes or movement sequences work without busy-looping.
5. **Player input** — if no script is running, read the held directions and determine which step the player is taking (or turning, or standing).
6. **Collision** — for each potential step direction, `GetMovementPermissions` looks up the destination tile's collision byte and returns a bitmask of permitted moves. Ledges, water, walls, ice — all filtered here.
7. **Tile events** — after any step, the engine checks whether the tile you're now standing on triggers anything: a warp (`CheckWarpCollision`), a coord event (`RunCurrentMapXYTriggers`), a grass/water encounter roll. This is the "step-on" event system.
8. **Facing events** — if you press `A`, the engine calls `CheckFacingSign` to see if you're facing a signpost, then checks whether you're facing an NPC and initiates dialogue.
9. **Camera** — if the player moved, `ScrollMapDown` / `ScrollMapUp` / `ScrollMapLeft` / `ScrollMapRight` updates one edge of the BG tile map and queues the scroll register update for the next VBlank.
10. **Sprites** — NPC structs are ticked (`map_objects.asm`), their positions updated, their animation frames advanced.
11. **VBlank** — at the end of the frame, the VBlank ISR transfers the queued sprite data (OAM DMA), queued tile updates (BG map row/column), and the queued scroll register values.

The whole cycle runs at 60 frames per second on hardware. Each individual step in the list is a few dozen instructions. The overworld feels smooth not because any single piece of it is fast, but because everything is minimal: every function does exactly one thing, allocates no memory, and returns immediately.

---

## Part Fourteen — Epilogue: the map as a promise

The deepest thing about this map system, the thing that becomes clear only after reading through all the layers, is that each map is a *promise* the codebase makes to the player. The promise has a shape: here is the terrain, here is who lives here, here is what will happen when you arrive, here is how you leave. Every header, every block grid, every script, every warp entry is part of keeping that promise.

The engine is the machinery that reads the promise and makes it real, frame by frame. The map setup script is the engine's contract with the map data: run these 20 steps in this order and the world will be coherent. The scripting VM is the map's way of modifying the engine's behaviour at specific moments. The palette system is the engine's awareness that the same map looks different at dawn than at midnight.

None of it is especially clever in isolation. The palette lookup is two array indices and a loop. The warp system is a coordinate comparison against a small list. The map setup script is a loop over a byte array. But together, at 60 frames per second, they produce something that feels inhabited — a world where the light changes as the hours pass, where NPCs pace their routes even when you're not watching, where stepping through any doorway brings you reliably and seamlessly to the other side.

That feeling of inhabitedness is, in the end, what the code is for. The bytes in the ROM are just an address book. The game is what happens when the engine reads it.

---

*The companion reference documents in this folder cover many of these systems from the "how do I edit it" perspective. [`maps-and-events.md`](maps-and-events.md) has the full macro syntax for maps, warps, and scripts. [`data-formats.md`](data-formats.md) covers trainer and wild data. [`memory-layout.md`](memory-layout.md) maps out every WRAM variable mentioned here. [`macros-and-constants.md`](macros-and-constants.md) explains the enum system that underlies all the `MAP_*`, `TILESET_*`, and `EVENT_*` constants. And [`map-rendering.md`](map-rendering.md) gives the exact Python-level pipeline if you want to reproduce what the engine does for static visualisation.*
