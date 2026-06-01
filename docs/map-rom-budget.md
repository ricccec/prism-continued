# Map ROM Budget

Analysis of map block data compression and ROM budget for new maps.

## Block data files

Maps are stored as raw block grids in `maps/blk/` with two files each:
- `*.ablk` — uncompressed source (width × height bytes, no header)
- `*.ablk.lz` — compressed version, included in the ROM via `INCBIN` in `maps/blockdata.asm`

369 maps total, 366 currently included in the ROM (3 are work-in-progress or runtime-only patches).

**Unused ablk files:**
- `LaurelForestBeach_NoWater.ablk.lz` — likely a leftover alternate
- `LaurelForestCharizardCaveButton1_BlockData.ablk.lz` — runtime block swap, not a full map load
- `MoundF1_BlownUp_BlockData.ablk.lz` — same, explosion-aftermath patch

## Compression

The build compresses every `.ablk` to `.ablk.lz` via a catch-all Makefile rule:

```makefile
%.lz: %
    utils/lzcomp -- $< $@
```

`lzcomp` (source in `utils/lz/`) is a multi-pass LZ compressor that tries all 96 method variants and picks the best output. It is already near-optimal for this format.

**The format** is the GBC/Crystal LZ variant with 7 command types: literal copy, byte repeat, pair repeat, zero fill, and three back-reference variants (normal, bit-flipped, reversed). The decompressor is in `home/decompress.asm`. It has no format header or detection logic — it always decompresses unconditionally, terminated by `$FF`.

**Overall compression:** 71,162 bytes raw → 44,962 bytes compressed (37% reduction).

### Compression by map size

| Tier | Maps | Raw (B) | LZ (B) | Ratio |
|------|------|---------|--------|-------|
| ≤ 20 bytes (tiny rooms) | 56 | 942 | 1,009 | **107% — LZ expands them** |
| ≤ 50 bytes (small rooms) | 67 | 2,379 | 1,951 | 82% |
| ≤ 100 bytes (medium interior) | 64 | 5,596 | 3,575 | 64% |
| ≤ 200 bytes (small dungeon) | 57 | 9,091 | 5,914 | 65% |
| ≤ 400 bytes (large dungeon/gym) | 84 | 27,371 | 17,955 | 66% |
| ≤ 700 bytes (city/route) | 29 | 15,154 | 9,045 | 60% |
| > 700 bytes (huge outdoor) | 12 | 10,629 | 5,513 | 52% |

The 56 smallest maps (≤ 20 bytes: elevators, gate corridors, single-purpose rooms) are actually made **larger** by compression — 67 bytes of wasted ROM. Storing them raw would save those bytes, but would require a flag in the map header and a branch in `ChangeMap` to skip decompression. Not worth it for 67 bytes.

Maps > 50 bytes average **276 bytes raw → 171 bytes compressed**.

## ROM budget for new maps

Compiled sizes from `pokeprism_nodebug.map` across 450 maps:

| Component | Total (B) | Per-map avg (B) |
|-----------|-----------|-----------------|
| Map scripts | 197,579 | 439 |
| Map block data | 44,168 | 98 |
| Map headers (×2) | 10,654 | 24 |
| Map events | 8,370 | 19 |
| **Total** | **260,771** | **~580** |

**ROM free (ROMX): 28,254 bytes → ~48 average maps in theory.**

### The bank fragmentation problem

Map scripts are the dominant cost (76%) and land in banked sections. Those banks are nearly exhausted:

- Only **8,488 bytes free** across all banks currently containing map scripts
- Bank #40 is the only one with meaningful room: 2,574 bytes (~5–6 average scripts)
- The remaining ~19,766 free bytes are in banks used for other things

### What actually saves you

Since every map header stores a `dba` (bank + address) pointer to its scripts and block data, new map data can go in **any** bank. Opening a new `SECTION "Map Scripts N", ROMX` fragment lets the linker place it in whatever bank has room. The **28,254 byte global ceiling is the real constraint**, not bank fragmentation.

The 439 B/map script average is also skewed by large scripted maps (PrisonF1 ~13 KB source, FirelightPalletPath1F ~13.7 KB source). A simple interior — one NPC, two warps, no events — compiles to roughly **100–150 bytes** of script, putting the total cost of a simple new map closer to **~300 bytes**.

## Route map sub-analysis

74 Route maps have block data files; 86 have script files (some gate/sub-maps share or omit a blk).

### Block data

| | Routes | All maps |
|---|---|---|
| Raw avg | 203 B | 193 B |
| LZ avg | 123 B | 122 B |
| Compression ratio | 61% | 63% |

Routes are slightly larger in footprint but compress marginally better (outdoor terrain is more repetitive). The 24 smallest route entries (≤ 50 bytes) are gates and indoor sub-maps. Filtering to actual outdoor routes (> 50 bytes, 50 maps) pushes the raw average to **287 B** — the largest being Route48 and Route65 at 720 bytes, Route80 at 675 bytes.

### Scripts and NPCs

| | Routes | Non-routes |
|---|---|---|
| Script source avg | 1,928 B | 2,442 B |
| `person_event` / `trainer` per map avg | 4.2 | 4.0 |

Routes actually have **smaller scripts** than non-route maps on average. Cities, gyms, labs, and dungeons carry more complex event logic, so they dominate script size. NPC count is essentially identical across both categories (~4 per map).

### Known dead-space cases

Three maps have significant wasted block data worth revisiting if ROM budget tightens.

**Route54** (30×9 = 270 B raw → 86 B LZ, 32%): columns 0–18 (19 of 30) are solid cliff (0x2c) on every row — 171 identical blocks with no events, warps, or connections touching them. All content is in columns 19–29. Trimming to 11×9 would require updating `mapgroup ROUTE_54, 9, 11`, all event x-coordinates (subtract 38 steps), and rebuilding the .ablk. Estimated LZ savings: ~25–30 bytes.

**Route64** (45×9 = 405 B raw → 206 B LZ, 51%): the map acts as an L-junction — a short vertical strip on the left serving the Route59 south connection (bottom edge, cols 0–4 only) and a horizontal corridor on the right connecting Naljo Border to Hayward City. The left ~16 columns are very uniform. The LZ ratio is the worst among outdoor routes (51% vs. 61% average) because the block variety is high, making dead corners more expensive. A vertical split around column 17 would produce two cleaner maps but requires wiring a new connection, adjusting the wild tables, and re-targeting all events.

**SeviiIsland1** (60×21 = 1,260 B raw → 498 B LZ, 38%): large water and cliff regions on opposite corners. Despite the wasted corners, the LZ ratio is already excellent (38%) because uniform areas compress to nearly nothing. The overhead of splitting (second set of headers, connection strip, re-wiring warps) would likely cost more bytes than it saves. Low priority.

### Cost estimate for a new route

A typical outdoor route (medium-sized, ~270–360 B raw block data, ~6 trainers + items) would cost roughly:

| Component | Estimate |
|---|---|
| Block data (compressed) | ~165–220 B |
| Map script | ~400–600 B compiled |
| Headers + events | ~43 B |
| **Total** | **~610–860 B** |

Slightly above the all-map average of ~580 B, driven by the larger block footprint. Script cost is actually no higher than average.
