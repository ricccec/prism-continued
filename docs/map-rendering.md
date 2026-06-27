# Map Visual Rendering — How a Map Frame Is Composed

This document explains the full data pipeline that transforms raw source files into a rendered RGB image of a map. The devtool `prism-mapview` (in `pokeprism-devtools`) uses this pipeline.

---

## High-level overview

```
ROM map header
  ├── tileset_id       → which tileset's tile/meta/attr/gfx files to load
  └── permission       → determines which palette color table to use

maps/blk/<Name>.ablk.lz
  └── block grid (height × width bytes, row-major)

tilesets/<id>_metatiles.bin   → block_id → 4 tile IDs (TL/TR/BL/BR)
tilesets/<id>_attributes.bin  → block_id → 4 palette-slot indices (0–7)
gfx/tilesets/<id>.2bpp[.lz]  → tile_id  → 8×8 pixels (2bpp, indices 0–3)
tilesets/bg.pal (+ special)   → palette-slot + time-of-day → 4 RGB colors

Final image: each block → 16×16 px (2×2 tiles × 8×8 px per tile)
```

---

## 1. Map header (ROM)

Each map has a **primary header** (9 bytes) and a **secondary header** (12 bytes) embedded in the compiled ROM. Their locations are found by walking:

```
sym["MapGroupPointers"]  →  MapGroup<N>  →  primary header (9 bytes per map)
```

Primary header layout:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | Bank of secondary header |
| **1** | **1** | **Tileset ID** (0–52) |
| **2** | **1** | **Permission** (bits 0–2 used for palette table lookup) |
| 3 | 2 | Pointer to secondary header |
| 5 | 1 | Location/landmark ID |
| 6 | 1 | Music ID |
| 7 | 1 | Time-of-day << 4 \| fishing group |
| 8 | 1 | (padding) |

Secondary header layout:

| Offset | Size | Field |
|--------|------|-------|
| 0 | 1 | Border block ID |
| 1 | 1 | **Height** (in blocks) |
| 2 | 1 | **Width** (in blocks) |
| 3 | 1 | Blockdata bank |
| 4 | 2 | Blockdata ROM address |
| 6–11 | — | Script/event headers, connection bitmask |

Source: `engine/map_headers.asm`, parsed by `pokeprism_devtools.blockdata.load()`.

---

## 2. Block grid (map blockdata)

`maps/blk/<MapName>.ablk.lz` contains an LZ-compressed flat array of `height × width` bytes, row-major. Each byte is a **block ID** (0–255) indexing into the tileset's metatile table.

Decompressed with `pokeprism_devtools.lz.decompress()`. See `docs/maps-and-events.md` for the BLK format and `home/decompress.asm` for the LZ algorithm.

---

## 3. Tileset files

All per-tileset data files live under `tilesets/` and `gfx/tilesets/`. Both compressed (`.lz`) and uncompressed versions exist in the source tree for most tilesets.

### 3a. Metatiles — `tilesets/<id:02d>_metatiles.bin`

**16 bytes per block ID**, 256 entries total (4096 bytes).  
Source: `wDecompressedMetatiles:: ds 256 * 16` in `wram.asm`.

Each entry is a row-major 4×4 grid of tile IDs:

```
byte  0  1  2  3   ← row 0 (y = 0–7 px)
byte  4  5  6  7   ← row 1 (y = 8–15 px)
byte  8  9 10 11   ← row 2 (y = 16–23 px)
byte 12 13 14 15   ← row 3 (y = 24–31 px)
```

A block is a **4×4 tile arrangement = 32×32 pixels**. Each tile ID indexes the tileset GFX table.

### 3b. Attributes — `tilesets/<id:02d>_attributes.bin`

**16 bytes per block ID**, same 256-entry × 16-byte layout as metatiles.  
Source: `wDecompressedAttributes:: ds 256 * 16` in `wram.asm`.

Each byte is a **BG palette slot index** (0–7) for the corresponding tile in the block (same row-major 4×4 ordering). Individual tiles within the same block can use different palette slots.

### 3c. Tile graphics — `gfx/tilesets/<id:02d>.2bpp[.lz]`

**16 bytes per tile**, Game Boy 2bpp format. Each byte pair encodes one 8-pixel row:

```
row byte 0 = low-plane bits  (bit 7 → leftmost pixel)
row byte 1 = high-plane bits
pixel value = (low_bit) | (high_bit << 1)   →  0, 1, 2, or 3
```

Pixel value 0–3 is a palette index; the actual RGB color comes from the palette slot chosen by the attributes file (see §4).

Typically 128–256 tiles per tileset (2048–4096 bytes uncompressed).

### 3d. Collision — `tilesets/<id:02d>_collision.bin`

**1 byte per block ID** (1024 bytes). Encodes walkability/interaction flags. Not used for rendering.

---

## 4. Palette system

Palette selection replicates the logic in `engine/color.asm` (`LoadMapPals`). The process has two layers:

### Layer 1: permission byte → color index table

The map's **permission** value (bits 0–2 of primary header byte 2) determines which color table to consult:

| Permission | Constant | Color table |
|-----------|----------|-------------|
| 0 | — | OutdoorColors |
| 1 | TOWN | OutdoorColors |
| 2 | ROUTE | OutdoorColors |
| 3 | INDOOR | IndoorColors |
| 4 | CAVE | DungeonColors |
| 5 | PERM_5 | DungeonColors |
| 6 | GATE | IndoorColors |
| 7 | DUNGEON | DungeonColors |

Each color table has 4 rows (one per time-of-day: morn/day/nite/dark), each row containing 8 **palette indices** into `TilesetBGPalette`.

```
OutdoorColors (from engine/color.asm):
  morn: [0x00, 0x01, 0x02, 0x28, 0x04, 0x05, 0x06, 0x07]
  day:  [0x08, 0x09, 0x0a, 0x28, 0x0c, 0x0d, 0x0e, 0x0f]
  nite: [0x10, 0x11, 0x12, 0x29, 0x14, 0x15, 0x16, 0x17]
  dark: [0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f]

IndoorColors:
  morn/day: [0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x07]
  nite:     [0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x07]
  dark:     [0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x07]

DungeonColors:
  morn: [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07]
  day:  [0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f]
  nite: [0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17]
  dark: [0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d, 0x1e, 0x1f]
```

### Layer 2: palette index → RGB colors from `tilesets/bg.pal`

`bg.pal` is a text file (`engine/color.asm` includes it via `INCBIN`) containing all map BG palettes. Format:

```
\tRGB r, g, b     ; 5-bit values (0–31); blank lines separate palettes
```

Palettes are indexed sequentially (0, 1, 2, …). The file has 5 sections in order:
- **Indices 0x00–0x07**: "Morn" outdoor/default palettes
- **Indices 0x08–0x0f**: "Day" outdoor palettes
- **Indices 0x10–0x17**: "Nite" outdoor palettes
- **Indices 0x18–0x1f**: "Dark" outdoor palettes
- **Indices 0x20–0x26**: Indoor-specific palettes (used for morn+day in IndoorColors)
- **Indices 0x28–0x29**: Special water/cave substitutes (used in Outdoor morn/nite slot 3)

Converting 5-bit to 8-bit: `rgb8 = (v << 3) | (v >> 2)`.

### Layer 3: map-group roof palette (`tilesets/roof.pal`)

After filling all 8 BG palettes via the layers above, `LoadMapPals` applies one final override for any map that is not a special-tileset map. It uses the current **map group number** (`wMapGroup`) as an index into `RoofPals` (`tilesets/roof.pal`), then overwrites BG palette 6 colors 1–2 (`wOriginalBGPals + 6 palettes + 2`, 4 bytes):

```
offset = wMapGroup * 8          # each group = 4 RGB entries = 8 bytes
if time_of_day >= NITE:
    offset += 4                 # second pair of colors
copy 4 bytes → BG palette 6, colors 1–2
```

`roof.pal` is a plain-text RGBASM file (one `RGB r, g, b` per line). Each map group occupies exactly **4 consecutive `RGB` entries** (8 bytes): the first two are morning/day colors, the last two are night colors.

**Key consequence:** all maps in the same map group share one roof palette entry. Moving a map to a different group silently changes the two roof colors it inherits, even if nothing else in the map header changes. When re-grouping a map, check and update the corresponding entry in `tilesets/roof.pal`.

### Special tileset overrides (`LoadSpecialMapPalette`)

Some tileset IDs bypass the permission/bg.pal system entirely:

| Tileset constant | Palette file | Time-of-day |
|-----------------|--------------|-------------|
| `TILESET_TRAINER_HOUSE` | `tilesets/battle_tower.pal` | no (single fixed set) |
| `TILESET_TUNOD` | `tilesets/tunod.pal` | yes (×8 offset) |
| `TILESET_ESPO_FOREST` | `tilesets/espo_forest.pal` | yes |
| `TILESET_OLCAN_ISLE` | `tilesets/olcan_isle.pal` (own map) or `tunod.pal` (other maps) | yes |

The numeric IDs for these constants are resolved from `constants/tileset_constants.asm`.

---

## 5. Render pipeline summary

```
block_id = blocks[row * width + col]             # from blockdata
base     = block_id * 16                         # 16 bytes per block

tile_ids  = metatiles[base : base+16]            # 4×4 tile IDs, row-major
pal_slots = attributes[base : base+16]           # palette slot per tile (0–7)

for i, (tid, slot) in enumerate(zip(tile_ids, pal_slots)):
    pixels = decode_2bpp_tile(gfx, tid)          # 8×8 array of 0–3 indices
    palette = palettes[slot]                     # 4 RGB tuples from §4
    dest_x  = (col * 4 + i % 4) * 8
    dest_y  = (row * 4 + i // 4) * 8
    paste pixels → image at (dest_x, dest_y) using palette
```

Each block becomes a 32×32 pixel region (4×4 tiles × 8px/tile). The final image is `width*32 × height*32` pixels.

---

## 6. Cache and invalidation

Rendered images are cached as `<repo>/.devtools/<mapname>.bmp`. A cached image is valid as long as it is **newer than the ROM file** (`pokeprism_nodebug.gbc` or `pokeprism.gbc`). Rebuilding the ROM invalidates all cached renders.

---

## Related source files

| File | Purpose |
|------|---------|
| `engine/color.asm` | `LoadMapPals`, `LoadSpecialMapPalette`, `TilesetBGPalette` |
| `tilesets/tilesets.asm` | Tileset GFX/meta/coll/attr table |
| `tilesets/tileset_headers.asm` | `tileset` macro definition |
| `tilesets/bg.pal` | Master BG palette data |
| `tilesets/*.pal` | Special per-tileset palette overrides |
| `constants/tileset_constants.asm` | `TILESET_*` numeric constants |
| `constants/map_dimension_constants.asm` | Map names, groups, and block dimensions |
| `home/decompress.asm` | LZ decompressor (ported to Python in `lz.py`) |
