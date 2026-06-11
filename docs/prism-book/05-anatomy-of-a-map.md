# Chapter 5 — Anatomy of a Map

*Every map in Prism is four things at once, and most of the interesting work happens in the gaps between them.*

---

## 5.1 What Is a Map?

Ask the compiler and it will say: a label, a few SECTION directives, and a handful of macros. Ask the engine and it will say: a pair of integers — a map group and a map number. Ask the player and they will say: a town they walked through once, a cave that nearly got them lost.

All three answers are right. But as an engineer reading the source, you need to hold four separate data structures in mind simultaneously, because "map" is overloaded across all of them:

1. **The block grid** — a flat byte array, one byte per block position, in a compressed binary file (`.blk.lz`). This is the visual layout: which terrain occupies which square.

2. **The primary header and secondary header** — small, fixed-size metadata records embedded in ROM that describe the map's tileset, dimensions, permission type, music, and how to find everything else. These are the engine's address book.

3. **The map script header** — a table of triggers and callbacks encoded as bytecode scripts. This is where story events, fly-point registration, and frame-by-frame callbacks live.

4. **The map event header** — the list of warps, coordinate triggers, signposts, and NPC definitions that make the map interactive.

This chapter is about numbers 1 and 2, and the rendering pipeline that turns a block grid into pixels. Numbers 3 and 4 — scripts, warps, NPCs — are covered in Chapter 7, though you will see them named repeatedly here because the headers point to them.

---

## 5.2 Map Identity: Group and Number

Every map in Prism is uniquely identified by two bytes: a **map group** and a **map number**. Both are one-indexed. The runtime keeps the current values in `wMapGroup` and `wMapNumber`.

Group and number are defined at build time via the `mapgroup` macro in `macros/map.asm`:

```asm
MACRO mapgroup
GROUP_\1 EQU const_value
    enum MAP_\1
\1_HEIGHT EQU \2
\1_WIDTH EQU \3
ENDM
```

One invocation defines three constants: `GROUP_CAPER_RIDGE`, `MAP_CAPER_RIDGE`, and the block dimensions `CAPER_RIDGE_HEIGHT` / `CAPER_RIDGE_WIDTH`. The `constants/map_dimension_constants.asm` file contains every `mapgroup` call for all 461 maps.

The group and number together index into a two-level pointer table. The anchor of that table — `MapGroupPointers` — is declared at the top of `maps/map_headers.asm`:

```asm
SECTION "Map Headers", ROMX
MapGroupPointers::
    dw MapGroup1
    dw MapGroup2
    dw MapGroup3
    ; ... 95 entries total
```

Each entry is a two-byte pointer to the first primary header in that group. To reach map group *G*, map number *N*, the engine calls `GetAnyMapHeaderPointer` in `home/map.asm`:

```asm
GetAnyMapHeaderPointer::
; inputs: b = map group, c = map number
; outputs: hl → the primary header

    push bc             ; save map number for later

    dec b               ; groups are 1-indexed
    ld c, b
    ld b, 0
    ld hl, MapGroupPointers
    add hl, bc          ; each pointer is 2 bytes …
    add hl, bc          ; … so advance 2 × (group - 1)

    ld a, [hli]
    ld h, [hl]
    ld l, a             ; hl → first header in this group
    pop bc              ; restore map number

    dec c               ; map numbers are also 1-indexed
    ld b, 0
    ld a, 9
    rst AddNTimes       ; step forward 9 bytes × (map number - 1)
    ret                 ; hl → the primary header
```

The `rst AddNTimes` is a one-byte call to a restart vector that multiplies `a` by `bc` and adds to `hl`. It appears throughout the map code wherever fixed-size records must be indexed. The final result is a pointer directly into the primary header — no searching, no hashing, pure arithmetic.

---

## 5.3 The Primary Header

The primary header is nine bytes, declared by the `map_header` macro:

```asm
; macros/map.asm
MACRO map_header
\1_MapHeader:
    db BANK(\1_SecondMapHeader), \2, \3
    dw \1_SecondMapHeader
    db \4, \5
    dn \6, \7
    db \8
ENDM
```

The arguments, in order: label, tileset, permission, landmark, music, phone-service flag, time-of-day override, fishing group. The emitted layout:

| Offset | Size | Field | Source argument |
|--------|------|-------|-----------------|
| 0 | 1 | Bank of secondary header | auto (`BANK(...)`) |
| 1 | 1 | Tileset ID | `\2` |
| 2 | 1 | Permission | `\3` |
| 3–4 | 2 | Pointer to secondary header | auto (`dw \1_SecondMapHeader`) |
| 5 | 1 | Landmark ID | `\4` |
| 6 | 1 | Music ID | `\5` |
| 7 | 1 | High nibble: phone-service flags; low nibble: time-of-day override | `dn \6, \7` |
| 8 | 1 | Fishing group | `\8` |

A concrete example from `maps/map_headers.asm`:

```asm
MapGroup2:
    map_header CaperRidge, TILESET_NALJO_2, TOWN, CAPER_RIDGE, \
               MUSIC_NEW_BARK_TOWN, 0, PALETTE_AUTO, FISHGROUP_SHORE
```

This nine-byte record tells the engine: Caper Ridge uses tileset `NALJO_2`, is a `TOWN`-permission outdoor map, belongs to the `CAPER_RIDGE` landmark cluster, plays `NEW_BARK_TOWN` music, has no phone-service override, uses automatic time-of-day palettes, and supports the shore fishing table. Everything the overworld needs to initialize a session on this map is in those nine bytes — or reachable from the secondary header pointer they contain.

The reason the primary header carries the bank of the secondary header (byte 0) is ROM banking: the secondary header might live in a different 16 KiB bank from the primary, so the bank must be loaded before the pointer can be followed.

---

## 5.4 The Secondary Header

The secondary header is reached by switching to the bank at primary-header byte 0, then following the pointer at bytes 3–4. It is declared by `map_header_2`:

```asm
; macros/map.asm
MACRO map_header_2
\1_SecondMapHeader::
    db \3               ; border block ID
    db \2_HEIGHT, \2_WIDTH
    dba \1_BlockData    ; bank (1 byte) + address (2 bytes) of block grid
    dba \1_MapScriptHeader
    dw \1_MapEventHeader
    db \4               ; connection bitmask
ENDM
```

`dba` is a three-byte emission: one byte for the bank, two bytes for the 16-bit address. The layout:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | Border block ID |
| 1 | 1 | Height (in blocks) |
| 2 | 1 | Width (in blocks) |
| 3–5 | 3 | `dba` — bank + address of block data |
| 6–8 | 3 | `dba` — bank + address of map script header |
| 9–10 | 2 | Pointer to map event header |
| 11 | 1 | Connection bitmask |

The **border block** is the block ID drawn around the edges of `wOverworldMap` in positions that have no valid map data — the visual filler you see at map corners. Each map declares its own; a route over water uses a water block, a cave uses a wall block.

The **connection bitmask** is a four-bit field: bit 3 = north, bit 2 = south, bit 1 = west, bit 0 = east. If a bit is set, a `connection` record follows immediately in the same `maps/second_map_headers.asm` file:

```asm
; maps/second_map_headers.asm
map_header_2 CaperRidge, CAPER_RIDGE, 53, NORTH | EAST
connection north, ROUTE_70, Route70, 5, 0, 10, CAPER_RIDGE
connection east,  ROUTE_71_WEST, Route71West, 0, 0, 9, CAPER_RIDGE
```

Connection records encode the precise strip alignment between neighbors — which column of the northern map's bottom edge aligns with which column of this map's top buffer. These are consumed by `FillMapConnections` during block loading, and the full mechanism (the 3-block border buffer and how scroll-connection transitions work) is examined in detail in Chapter 6.

The engine copies the secondary header's twelve bytes into WRAM at `wMapHeader` via `CopySecondMapHeader` (`home/map.asm`):

```asm
CopySecondMapHeader::
    ld de, wMapHeader
    ld bc, 12       ; size of the second map header
    rst CopyBytes
    ret
```

After that call, `wMapWidth`, `wMapHeight`, `wMapBlockDataBank`, `wMapBlockDataPointer`, and `wMapConnections` are all populated and ready.

---

## 5.5 The Block Grid

The visual layout of a map is a flat, row-major byte array: one byte per block position, `height × width` bytes total. Each byte is a **block ID** (0–255) — an index into the tileset's metatile, attribute, and collision tables.

Block grids live in compressed binary files under `maps/blk/`, named like `CaperRidge.ablk.lz`. The `.lz` extension signals Prism's LZ compression variant (documented in `home/decompress.asm`). The format uses seven command types distinguishable by the top three bits of a control byte:

- `LZ_DATA` (`000`): emit N literal bytes verbatim
- `LZ_REPEAT_1` (`001`): emit the same byte N times
- `LZ_REPEAT_2` (`010`): alternate two bytes N times
- `LZ_ZERO` (`011`): emit N zero bytes
- `LZ_COPY_NORMAL` (`100`): back-reference N bytes from a signed offset in already-decompressed output
- `LZ_COPY_FLIPPED` (`101`): same but with each byte bit-flipped
- `LZ_COPY_REVERSED` (`110`): same but in reverse order

The length field is 5 bits (0–31 bytes), expandable to 10 bits via the `LZ_LONG` escape (`111`). A `$ff` byte terminates the stream. The back-reference commands — especially `LZ_COPY_NORMAL` and `LZ_COPY_REVERSED` — exploit the heavy repetition in map data: grass patches, road tiles, room walls all compress down to short back-references.

At runtime, `LoadBlockData` in `home/map.asm` orchestrates the decompression:

```asm
LoadBlockData::
    ; (set up hVBlank for safe WRAM access)
    ld hl, wOverworldMap
    ld bc, wOverworldMapEnd - wOverworldMap
    xor a
    call ByteFill           ; zero the entire overworld buffer first

    call ChangeMap          ; decompress current map into wOverworldMap
    call FillMapConnections ; fill the 3-block border from neighbors

    ld a, MAPCALLBACK_TILES
    call RunMapCallback     ; trigger any tile-modifying map callbacks
    ; (restore hVBlank)
    ret
```

`ChangeMap` does the actual decompression, landing data at `wDecompressScratch`, then copying it row by row into the interior of `wOverworldMap` at the correct offset:

```asm
ChangeMap::
    ld a, [wMapBlockDataBank]
    ld b, a
    ld hl, wMapBlockDataPointer
    ld a, [hli]
    ld h, [hl]
    ld l, a             ; b:hl = ROM address of compressed block data

    ld a, [wMapWidth]
    ld d, a
    ld a, [wMapHeight]
    ld e, a

    ; decompress into wDecompressScratch (WRAM bank 6)
    call FarDecompressAtB_D000

    ; stride = width + 6  (6 = 3 border cols on each side)
    ld a, d
    add 6
    ldh [hConnectionStripLength], a

    ld hl, wOverworldMap
    ; skip 3 border rows × stride, then 3 border columns
    ; ... row-by-row copy from wDecompressScratch into wOverworldMap
```

### The 3-Block Border

`wOverworldMap` is declared in WRAM0 as a 1300-byte buffer (`ds 1300`, at address `$c800`). It is larger than any single map's block data. The current map's blocks occupy the interior of this buffer; a 3-block-wide border surrounds them on all sides.

That border serves two purposes. First, it provides visual continuity: the camera can look 3 blocks past the map edge and still see valid terrain (filled from the neighboring maps by `FillMapConnections`). Second, `GetCoordTile` uses coordinates that include this offset — the formula `wOverworldMap + 1 + e/2 × stride + d/2` incorporates the border rows in the stride — which means there are never out-of-bounds reads when checking collision near a map edge.

After `ChangeMap` fills the interior, `FillMapConnections` decompresses each neighbor (north, south, west, east in turn) and copies the 3-row or 3-column strip nearest the shared edge into the appropriate border region of `wOverworldMap`. The `connection` macro records the exact source offset and destination pointer for each direction, calculated from the neighbors' dimensions at assemble time.

---

## 5.6 Tilesets — The Three Tables

Every primary header has a tileset ID. That ID points to a set of binary files in `tilesets/` that define how block IDs translate to visual output and collision behavior. There are three tables:

### Metatiles — `tilesets/<id>_metatiles.bin`

The metatile table maps each block ID to a **4×4 grid of 8-bit tile IDs**. There are 256 possible block IDs, each with 16 tile-ID bytes = 4096 bytes total. This is the size of `wDecompressedMetatiles` in WRAM bank 5:

```asm
; wram.asm
SECTION "Metatiles", WRAMX
wDecompressedMetatiles::
    ds 256 * 16
```

The 16 bytes for block ID *B* begin at offset `B × 16`. They describe a 4×4 arrangement of 8×8-pixel tiles, read left-to-right, top-to-bottom:

```
byte  0  1  2  3    ← top row    (y = 0–7 px relative to block origin)
byte  4  5  6  7    ← row 1      (y = 8–15 px)
byte  8  9 10 11    ← row 2      (y = 16–23 px)
byte 12 13 14 15    ← bottom row (y = 24–31 px)
```

A single block is therefore **32×32 pixels** (4 tiles × 8 px/tile in each dimension). The metatile system exists because maps repeat the same terrain combinations constantly — grass corner, road edge, cliff face — and describing 256 named blocks is far more compact than describing millions of individual 8×8 tiles.

### Attributes — `tilesets/<id>_attributes.bin`

The attribute table has the same shape as the metatile table: 256 × 16 bytes, stored at `wDecompressedAttributes`. Each byte is a **BG palette slot index** (0–7) for the corresponding tile in the same row-major 4×4 position.

The Game Boy Color supports eight active background palettes simultaneously, each with four colors. The attribute table says which of the eight slots each individual tile within a block draws from. Tiles within the same block can use different palette slots — a doorway block might use one slot for the wooden frame and another for the stone surround. The palette system that assigns actual RGB colors to those slots is described in Chapter 6.

### Collision — `tilesets/<id>_collision.asm`

The collision table is different in format: it is an assembly source file (`.asm`), not a binary, assembled into a four-byte-per-block-ID binary at build time. The source files use the `tilecoll` macro. Here are the first ten entries of `tilesets/00_collision.asm`:

```asm
; tilesets/00_collision.asm (blocks 0–9)
    tilecoll WALL,      WALL,      WALL,      WALL
    tilecoll FLOOR,     FLOOR,     FLOOR,     FLOOR
    tilecoll FLOOR,     FLOOR,     FLOOR,     FLOOR
    tilecoll TALL_GRASS,TALL_GRASS,TALL_GRASS,TALL_GRASS
    tilecoll FLOOR,     FLOOR,     FLOOR,     FLOOR
    tilecoll WALL,      WALL,      WALL,      WALL
    tilecoll FLOOR,     FLOOR,     FLOOR,     FLOOR
    tilecoll WALL,      WALL,      WALL,      FLOOR
    tilecoll WALL,      WALL,      WALL,      WALL
    tilecoll WALL,      WALL,      WALL,      WALL
```

The four arguments are the **four 2×2-tile quadrants** of the block: top-left, top-right, bottom-left, bottom-right. Each argument is a collision constant from `constants/collision_constants.asm`. The assembled result is four bytes per block, stored at `wDecompressedCollision` (WRAM bank 5, `256 × 4` bytes).

### Loading All Three

`LoadMetatilesTilecoll` in `home/map.asm` decompresses all three tables into WRAM:

```asm
LoadMetatilesTilecoll:
    ld hl, wTilesetBlocksBank
    ld de, wDecompressedMetatiles
    ld c, BANK(wDecompressedMetatiles)
    call .Decompress

    ld hl, wTilesetAttributesBank
    ld de, wDecompressedAttributes
    ld c, BANK(wDecompressedAttributes)
    call .Decompress

.collision
    ld hl, wTilesetCollisionBank
    ld de, wDecompressedCollision
    ld c, BANK(wDecompressedCollision)
    ; fallthrough to .Decompress
```

`.Decompress` reads the bank and ROM pointer from the tileset header word at `hl`, then calls `FarDecompressAtB_DE` with the appropriate WRAM bank in `c`. All three tables land in WRAM bank 5 and stay there for the lifetime of the current map.

---

## 5.7 The Tile GFX Layer

The metatile and attribute tables index into two parallel data sources:

- **Tile graphics** — `gfx/tilesets/<id>.2bpp[.lz]`: one 16-byte Game Boy 2bpp tile per index. The GFX file is loaded into Video RAM by `LoadTileset` (called separately from `LoadMetatilesTilecoll`).
- **Palette colors** — selected by the attribute table's slot index, with the actual RGB values coming from the palette system. Chapter 6 covers that fully.

The 2bpp format: each 8×8 tile is 16 bytes. Bytes come in pairs; within each pair, byte 0 is the low bit-plane and byte 1 is the high bit-plane. Bit 7 of each byte corresponds to the leftmost pixel. For pixel *i* in a row: `value = ((low >> (7-i)) & 1) | (((high >> (7-i)) & 1) << 1)`, yielding a 2-bit index 0–3 into the four-color palette.

---

## 5.8 The Rendering Indirection

The full path from a map coordinate to a rendered pixel is a chain of four lookups:

```
(col, row) → block_id
              ↓  wOverworldMap[row/2 × (width+6) + col/2]
block_id   → 16 tile_ids   (from wDecompressedMetatiles[block_id × 16])
           → 16 pal_slots  (from wDecompressedAttributes[block_id × 16])
tile_id    → 128 pixel values  (from VRAM 2bpp data, 16 bytes per tile)
pal_slot   → 4 RGB colors     (from palette system — see Chapter 6)
```

Concretely: a 10-wide × 8-tall map produces a 320×256-pixel image. Each block is 32×32 pixels. The camera shows a 160×144 viewport (the GBC screen), scrolled into the `wOverworldMap` buffer via BG scroll registers `rSCX`/`rSCY`.

The BG layer on the GBC is a 32×32-tile torus. The game maintains a sliding window into this torus. When the player takes a step, `ScrollMapDown`/`ScrollMapUp`/`ScrollMapLeft`/`ScrollMapRight` (all in `home/map.asm`) write one new row or column of tile IDs from `wOverworldMap` into the BG tile map via `UpdateBGMapRow`/`UpdateBGMapColumn`, then queue a BG-map-update flag for VBlank. The hardware scroll registers shift the visible window by up to one tile per step, with pixel-level animation driven by sprite-layer movement. The result: smooth scrolling from entirely table-driven data.

---

## 5.9 Collision Types

The collision table uses typed byte constants, not boolean walkability flags. The full set is defined in `constants/collision_constants.asm`. A representative cross-section:

| Constant | Value | Behavior |
|----------|-------|----------|
| `COLL_FLOOR` | `$00` | Passable |
| `COLL_WALL` | `$07` | Impassable |
| `COLL_TALL_GRASS` | `$18` | Passable; triggers wild encounter roll |
| `COLL_SUPER_TALL_GRASS` | `$14` | Passable; higher encounter rate |
| `COLL_WATER` | `$29` | Surf-only passable |
| `COLL_WATERFALL` | `$33` | Waterfall mechanic |
| `COLL_ICE` | `$23` | Passable; ice-slide physics |
| `COLL_LEDGE_DOWN` | `$a3` | One-way ledge, must jump downward |
| `COLL_LEDGE_RIGHT` | `$a0` | One-way ledge rightward |
| `COLL_DOOR` | `$71` | Triggers warp on step |
| `COLL_CAVE` | `$7b` | Triggers warp on step |

`GetCoordTile` in `home/map.asm` handles the full lookup chain:

```asm
GetCoordTile::
; Input: d = map X, e = map Y
; Output: a = collision byte

    call GetBlockLocation   ; hl → block ID byte in wOverworldMap
    ld a, [hl]
    and a
    jr z, .nope             ; block ID 0 → return -1
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl              ; hl = block_id × 4

    ld a, h
    add HIGH(wDecompressedCollision)
    ld h, a                 ; hl → base of this block's 4 collision bytes

    rr d                    ; carry = d bit 0 (right half of block?)
    jr nc, .nocarry
    inc l                   ; right-half → quadrant offset +1

.nocarry
    rr e                    ; carry = e bit 0 (bottom half of block?)
    jr nc, .nocarry2
    inc l
    inc l                   ; bottom-half → quadrant offset +2

.nocarry2
    ld a, BANK(wDecompressedCollision)
    jp GetFarWRAMByte       ; a = collision byte for this exact quadrant
```

`GetBlockLocation` computes `wOverworldMap + 1 + (e/2) × (wMapWidth + 6) + (d/2)` using the `srl`-then-`AddNTimes` pattern. The `+6` is the connection border width. The `rr d` / `rr e` bit-tests determine which of the four 2×2-pixel quadrants within the 32×32 block the coordinate falls in.

`GetMovementPermissions` calls `GetCoordTile` for the four adjacent tiles to build a permission bitmask, then checks the high-nibble warp convention (described below) against the standing tile itself.

### The High-Nibble Warp Convention

Many collision constants carry warp semantics in their high nibble. `COLL_HIGH_NYBBLE_WARPS` is `$70` (`112` decimal). Any collision byte whose high nibble equals `$7` — including `COLL_DOOR` (`$71`), `COLL_CAVE` (`$7b`), `COLL_WARP_CARPET_DOWN` (`$70`), `COLL_STAIRCASE` (`$7a`), `COLL_WARP_PANEL` (`$7c`), and so on — triggers the warp check. This is tested in `GetMovementPermissions.CheckHiNybble`:

```asm
.CheckHiNybble
    and $f0
    cp $b0
    ret z
    cp $c0
    ret
```

Wait — that tests `$b0` and `$c0`, not `$70`. The `$70`-family check is done earlier in `CheckWarpCollision` (called from `GetDestinationWarpNumber`), which explicitly tests whether `(tile & $f0) == COLL_HIGH_NYBBLE_WARPS`. The effect is that any block with the `$70` high nibble causes `CheckWarpTile` to fire, which walks the warp list and copies the destination to `wNextWarp`/`wNextMapGroup`/`wNextMapNumber`.

The elegance: a tileset author marks certain blocks with warp-class collision bytes, and the entire warp system activates automatically — no per-map configuration, no special event list entry. The block ID itself encodes "this is a door." Chapter 7 covers the full warp resolution and NPC event system.

---

## 5.10 The Tileset Table

The tileset IDs referenced in the primary header index into a table at `tilesets/tilesets.asm`. Each entry (a `tileset` macro invocation) records the bank and pointer for the tile GFX, the metatile binary, the attribute binary, and the collision binary. `LoadTilesetHeader` in `home/map.asm` copies the relevant entry into WRAM at `wTilesetBank`:

```asm
LoadTilesetHeader::
    ld hl, Tilesets
    ld bc, Tileset01 - Tileset00    ; size of one tileset entry
    ld a, [wTileset]
    rst AddNTimes                   ; step to the Nth entry

    ld de, wTilesetBank
    ld bc, Tileset01 - Tileset00
    ld a, BANK(Tilesets)
    call FarCopyBytes               ; copy entry into WRAM
```

After this call, `wTilesetBank`, `wTilesetBlocksBank`, `wTilesetAttributesBank`, and `wTilesetCollisionBank` are populated, and subsequent calls to `LoadTileset` (GFX) and `LoadMetatilesTilecoll` (metatiles + attributes + collision) can proceed.

---

## 5.11 Putting It Together: The Map Setup Sequence

Block grid loading and tileset loading are two steps in a larger map setup script. The full warp-entry sequence, defined in `engine/map_setup.asm`, runs approximately 20 named steps in order. The relevant steps for this chapter:

```
LoadMapAttributes    — parse headers, read connections, warp/NPC/script tables
LoadBlockData        — decompress block grid → wOverworldMap + fill border strips
LoadGraphics         — decompress tile GFX → VRAM (calls LoadTileset)
LoadMetatilesTilecoll — decompress metatile/attr/collision → WRAM bank 5
LoadMapPalettes      — compute and apply the 8 BG palettes from permission + ToD
```

Notice the ordering constraint: `LoadBlockData` must run before the camera can render anything, and `LoadMetatilesTilecoll` must run before collision checks are valid. `LoadGraphics` and `LoadMapPalettes` must run before the LCD is re-enabled — both write to VRAM and palette registers that the hardware reads during drawing. The setup sequence enforces this by wrapping all VRAM writes between `DisableLCD` and `EnableLCD` steps.

---

## 5.12 Reference: Key Files and Symbols

| File | What it contains |
|------|-----------------|
| `maps/map_headers.asm` | `MapGroupPointers` table; all primary headers via `map_header` |
| `maps/second_map_headers.asm` | All secondary headers via `map_header_2` and `connection` |
| `macros/map.asm` | `map_header`, `map_header_2`, `connection`, `warp_def`, `person_event`, … |
| `home/map.asm` | `GetAnyMapHeaderPointer`, `LoadBlockData`, `ChangeMap`, `FillMapConnections`, `LoadMetatilesTilecoll`, `GetCoordTile`, `GetBlockLocation` |
| `tilesets/<id>_metatiles.bin` | 256 × 16 byte metatile table (block → tile IDs) |
| `tilesets/<id>_attributes.bin` | 256 × 16 byte attribute table (block → palette slots) |
| `tilesets/<id>_collision.asm` | 256 × 4 byte collision table (block → quadrant bytes) |
| `gfx/tilesets/<id>.2bpp[.lz]` | Tile pixel data, 16 bytes per tile |
| `constants/collision_constants.asm` | All `COLL_*` constants |
| `constants/map_dimension_constants.asm` | All `GROUP_*`, `MAP_*`, `*_HEIGHT`, `*_WIDTH` constants |
| `home/decompress.asm` | LZ decompressor (`_Decompress`, seven command types, `$ff` terminator) |
| `wram.asm` | `wOverworldMap` (`$c800`, 1300 bytes), `wDecompressedMetatiles`, `wDecompressedAttributes`, `wDecompressedCollision` |

---

## Where to Next

You now understand what a map is as data, how the engine finds it, and how raw block IDs become tile grids on screen. One large subject was deliberately deferred: the **palette system** that transforms 2-bit pixel indices and 3-bit palette slot indices into actual RGB colors — including the time-of-day fade, the permission-based color table lookup, and special per-tileset overrides.

That is Chapter 6 — *Colour, Light, and Loading* — which also covers the full camera scrolling mechanism, how the 3-block border enables seamless connection transitions, and the VRAM double-buffer scheme that makes every step smooth at sixty frames per second.
