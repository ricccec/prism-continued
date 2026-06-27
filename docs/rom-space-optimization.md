# ROM Space Optimization Strategies

A prioritized catalogue of ways to free ROM space in Pokémon Prism: what is
unused, what can be compressed, and what can be restructured without a noticeable
gameplay hit. Strategies are ranked by estimated bytes saved against
implementation complexity.

All figures were measured with the `prism-usage` devtool
([`pokeprism-devtools`](https://github.com/ricccec/pokeprism-devtools)) against
the committed link map, not estimated by eye. Re-run the commands shown to
re-verify after any RGBDS build.

---

## 1. Framing: what "tightly packed" actually means here

It is tempting to think the 2 MB cartridge is full. It is not.

```
$ prism-usage summary
ROM     1,904,839 / 2,097,152 bytes used   (90.8%)
        192,313 free across 128 banks
```

That 192 KB of "free" space is two completely different things:

| Pool | Size | Usable? |
|------|------|---------|
| Empty trailing banks `$77–$7f` (9 banks) | **~147 KB** | Yes — fully addressable, just unassigned |
| Bank `$76` + `$74` tails | ~16 KB | Yes |
| Scattered slivers across in-use banks | ~29 KB | Mostly **no** — 38 banks have <60 bytes each |

On top of that, the cart is MBC5: the ROM-size header could be raised and the
file grown to 4 MB. **So there is no cartridge wall.** What makes the ROM *feel*
tight is two narrower constraints:

1. **Bank 0 (home) has only 825 bytes free.** Home code is visible from every
   bank and is where `farcall`-able runtime routines must live. This is the one
   genuinely hard limit.
2. **Per-bank packing / fragmentation.** Data that must be co-located — audio
   samples needing `align 8`, map block data, code that calls within its own
   bank — can't grow even though whole banks sit empty elsewhere. See the bank
   layout in [`../contents/romx.link`](../contents/romx.link) and the map-data
   discussion in [`map-rom-budget.md`](map-rom-budget.md).

**Consequence for prioritization:** raw byte savings are good, but *moving things
out of bank 0* and *shrinking the two giant asset classes* (below) deliver more
real headroom than chasing kilobytes in already-comfortable banks. Also note the
ROM file is padded to 2 MB regardless — freeing banked content frees **bank
slots**, not file size, until you lower the ROM-size header.

### Where the space actually goes

Authoritative category totals (`prism-usage section <name>`, `prism-usage largest`):

| Category | ROM bytes | ~Banks | Notes |
|----------|----------:|-------:|-------|
| **Cry audio (`DED *`)** | **~457 KB** | 27 + smalls | DED 1–27 ≈ 409 KB; biggest single class |
| **Pokémon sprites (`Pics *`)** | **331 KB** | 30 | LZ-compressed 2bpp |
| **Map scripts (`Map Scripts *`)** | 198 KB | 28 | Event logic + embedded text |
| **Tilesets** | 117 KB | 11 | |
| **Music (`Songs *`)** | 115 KB | 20 | |
| **Overworld sprites** | 56 KB | 8 | |
| **Map block data** | 44 KB | 13 | Already LZ; see `map-rom-budget.md` |
| **Pokémon icons** | 24 KB | 5 | |

Cries + sprites alone are ~788 KB — about **41% of all used ROM**. That is where
the leverage is.

> **Build note.** The only link map currently in the tree is the **debug** build
> (`pokeprism.map` — its bank `$05` still contains a `Debug Menu` section). The
> shipped `pokeprism_nodebug.gbc` strips the debug-only sections via
> `debug_mode_flag`. Each strategy below is tagged **release**, **debug**, or
> **both**. Build a release map (`make nodebug`) and pass `--map
> pokeprism_nodebug.map` to compare apples to apples.

---

## 2. Master table (ranked by estimated savings)

Estimates are deliberately rough ranges — validate each with `prism-usage diff`
before/after. "Lossy?" flags anything a player could perceive.

| # | Strategy | Est. ROM saved | Complexity | Build | Lossy? |
|---|----------|---------------:|------------|-------|--------|
| S1 | Reduce cry (DED) fidelity / trim clip length | **100–180 KB** | Medium | both | ⚠ minor audible |
| S2 | Pokémon sprite (`Pics`) reduction | 30–120 KB | Med–High | both | ⚠ if lossy tier used |
| S5 | Compress dex / move / item description text | 20–40 KB | Med–High | both | No |
| S3 | Music (`Songs`) trim & dedup | 15–40 KB | Medium | both | Drop-tracks only |
| S9 | Trainer / learnset / wild-table dedup | 3–10 KB | Med–High | both | No |
| S4 | Strip debug sections | ~8 KB + gated code | Low | **debug only** | No |
| S8 | Variable-length name tables | 2–5 KB | Medium | both | No |
| S6 | Map block-data dedup / restructure | ~1–2 KB | High | both | No |
| S7 | Remove dead code & unused entries | <300 B | Low | both | No |
| S10 | Relieve bank-0 / home pressure | frees home, ~0 net | Medium | both | No |
| S11 | Claim empty banks `$77–$7f` / grow to 4 MB | escape valve | Low | both | No |

---

## 3. Strategy details

### Tier 1 — KB-scale wins

#### S1. Reduce cry (DED) audio fidelity / trim clip length
*Est. 100–180 KB · Medium · both · ⚠ minor audible*

Cry audio is the single largest thing in the ROM: `DED 1`–`DED 27` ≈ **409 KB**,
plus `DED small *` and headers ≈ **~457 KB total**. DED is a custom codec
(`dedenc.py`: resample → 4-bit delta → Huffman) decoded at runtime by
[`../home/ded.asm`](../home/ded.asm). There are only **104 unique `.ded` files**
(`audio/ded/*.ded`) for 260+ species — cries are *already shared* across
evolution families, so further dedup yields little. The remaining lever is
**fidelity**:

- Lower the target **sample rate** in `dedenc.py` (cries are sub-second SFX; a
  modest rate cut is barely perceptible on GBC speakers).
- **Trim trailing silence / clip length** before encoding.
- Re-encode all `audio/ded/*.wav → .ded` (the Makefile already runs `dedenc.py`),
  then rebuild.

A ~25–40% size cut across ~457 KB is **~110–180 KB**, freeing roughly 7–11 whole
banks (`$58`–`$70`). The work is a re-encode + listening QA pass, not a code
change — which is why it has the best return in the whole list.

- **Files:** `dedenc.py`, `audio/ded/`, `audio/ded.asm`, `home/ded.asm`
- **Measure:** `prism-usage section "DED 1"` … (per-section), or sum via
  `prism-usage largest -n 300 | grep '^DED'` before/after; `prism-usage diff`.
- **Risk:** cries sound slightly lower-fi. Pick the rate by ear; keep originals
  in git so you can re-encode at any quality.

#### S2. Pokémon sprite (`Pics`) reduction
*Est. 30–120 KB · Med–High · both · ⚠ at high end*

`Pics 1`–`Pics 21` (+ `Pics small *`) = **331 KB across 30 banks**, LZ-compressed
2bpp front/back sprites. The compression is already near-optimal (`lzcomp` tries
all 96 method variants), so lossless wins are modest:

- **Lossless:** dedup identical back-sprites or repeated animation frames across
  species; re-run `lzcomp` if any source changed. Likely single-digit KB.
- **Lossy (flag clearly):** reduce pic **dimensions** (e.g. 56×56 → smaller for
  species that don't need the detail) or **palette/detail**. This is where the
  30–120 KB lives, but it visibly changes sprites — reserve for a deliberate
  art pass.

- **Files:** `gfx/pics/`, the pic build script (`gfx.py` / `utils/pokepic`)
- **Measure:** `prism-usage section Pics`; `prism-usage diff`.
- **Risk:** lossy tier is player-visible. The lossless tier is safe but small.

#### S5. Compress description text (Pokédex / moves / items)
*Est. 20–40 KB · Med–High · both · lossless*

Description text is stored as raw charmap bytes, uncompressed:
`data/pokedex/entries/` (254 files, ~1 MB source),
`battle/moves/move_descriptions.asm`, and item descriptions. Adding an LZ or
dictionary-compression pass (the LZ decompressor already exists in
[`../home/decompress.asm`](../home/decompress.asm)) plus a decode hook in the
text path can reclaim 20–40 KB.

A lighter, complementary win: **phrase-template dedup** for boilerplate dex lines
("The X Pokémon", repeated height/weight phrasing) referenced by ID.

Note that **map scripts (198 KB)** also contain large amounts of embedded
dialogue; compressing that has the biggest text upside but the highest risk
(touches the script interpreter) — treat as a stretch goal under this strategy.

- **Files:** `data/pokedex/entries/`, `battle/moves/move_descriptions.asm`,
  `text.asm`, `home/decompress.asm`, the text-rendering path
- **Measure:** `prism-usage section "Pokedex Entries"`, `... "Text"`;
  `prism-usage diff`.
- **Risk:** decompression adds latency when a text box opens — keep it off the
  hot path / decode once into a buffer. No content change, so not lossy.

#### S3. Music (`Songs`) trim & dedup
*Est. 15–40 KB · Medium · both · lossless→drop-tracks*

`Songs *` = **115 KB across 20 banks**. Levers:

- **Dedup** shared instrument/envelope/pattern data between tracks.
- **Drop unused tracks** — cross-check every entry in
  [`../audio/music_pointers.asm`](../audio/music_pointers.asm) against actual
  `playmusic`/`musicheader` references; remove orphans.

- **Files:** `audio/music/`, `audio/music_pointers.asm`
- **Measure:** `prism-usage section Songs`; `prism-usage diff`.
- **Risk:** dedup is lossless; dropping a track is only safe once confirmed
  unreferenced.

### Tier 2 — Medium wins

#### S9. Trainer / learnset / wild-table dedup
*Est. 3–10 KB · Med–High · both · lossless*

Many trainers share identical 4-move pools, and many maps reuse identical wild
encounter tables. Define shared move-pool / wild-table tables referenced by ID
instead of inlining duplicates.

- **Files:** `trainers/`, `data/wild/`, `data/movesets/`
- **Measure:** `prism-usage section "Enemy Trainers"`, `... Wild`; `diff`.
- **Risk:** format change to the trainer/wild loaders — test battles and
  encounters thoroughly. No gameplay change if mappings are preserved.

#### S4. Strip debug sections
*Est. ~8 KB dedicated + scattered gated code · Low · debug build only*

The dedicated debug sections compile to **~8 KB** in the debug ROM
(`Debug Menu` 7,884 B in bank `$05` + `Debug Battle Tower` 171 B in `$14`), plus
`debug_mode_flag`-gated code scattered through other sections. (The often-quoted
"62 KB" is *source* size in `engine/debug_menu_contents.asm` etc., not ROM
bytes.) **The release build already excludes all of this** — so this strategy
only matters if you are tight in the *debug* build.

- **Files:** `engine/debug_menu_contents.asm`, `engine/debug_menu.asm`,
  `engine/main_menu_debug.asm`, `macros/debug_menu.asm`
- **Measure:** `prism-usage --debug section Debug`.
- **Risk:** none for release; for debug, only remove menus you don't use.

#### S8. Variable-length name tables
*Est. 2–5 KB · Medium · both · lossless*

Move / item / species names are stored fixed-width (e.g. 11 bytes, null-padded).
Repack as a packed blob + offset table.

- **Files:** `data/moves/move_names.asm`, `items/item_names.asm`, the species
  name table, and **every** name-read path (the offset indirection must be added
  everywhere a name is fetched).
- **Measure:** `prism-usage section "Move Names"` etc.; `diff`.
- **Risk:** broad but mechanical; a missed read site shows up immediately as
  garbled text.

#### S6. Map block-data dedup / restructure
*Est. ~1–2 KB · High · both · lossless*

Map block data is already LZ-compressed to 44 KB total. The only meaningful waste
is a few maps with large dead regions (Route54, Route64 — see
[`map-rom-budget.md`](map-rom-budget.md)). Trimming dead columns saves tens of
bytes each but requires remapping every event coordinate on that map.

- **Files:** `maps/blk/`, `maps/<MapName>.asm`; use `prism-map` / `prism-mapfit`.
- **Measure:** `prism-map <Name>`; rebuild and `prism-usage diff`.
- **Risk:** high effort for small gain — only worth it if a specific bank is
  blocking. Coordinate remap can break warps/NPCs if done carelessly.

### Tier 3 — Housekeeping

#### S7. Remove dead code & unused entries
*Est. <300 B · Low · both · lossless*

Small but some sit in the tightest banks (`$3c`, `$57` have 1 byte free), so
clearing them can unblock a co-located section:

- Unused tileset-anim wrappers `WriteTileFromBuffer_Bank1` /
  `WriteTileToBuffer_Bank1` (`tilesets/animations.asm`).
- 6 dummy `dbw 0, 0` effect-command slots
  (`battle/effects/effect_command_pointers.asm`) — 18 B.
- Unused first palette pointer in `.TilesetColorsPointers` (`engine/color.asm`).
- Unused item slot `$fe` (`items/item_attributes.asm`) and stray unused
  constants (`constants/battle_constants.asm`, `constants/engine_flags.asm`).

- **Measure:** `prism-usage check --max-bank-usage 99` to see which banks are at
  the edge; `prism-usage diff`.
- **Risk:** verify "unused" with a full-tree reference search before deleting
  (some labels flagged `; unused` are in fact referenced — e.g. `MAPOBJECT_E`).

### Tier 4 — Structural relief (frees the real constraint, not net bytes)

#### S10. Relieve bank-0 / home pressure
*Frees home headroom · Medium · both*

Bank 0's 825 free bytes is the actual blocker for new features. Audit
[`../home.asm`](../home.asm) / `home/` for routines that don't truly need to be
home-resident and move them into a banked section, calling them via `farcall`.
This doesn't reduce total ROM bytes, but it buys the scarcest resource in the
project.

- **Files:** `home/*.asm`, callers (convert `call` → `farcall`).
- **Measure:** `prism-usage bank 0` before/after.
- **Risk:** a routine called from an interrupt or mid-bankswitch must stay home —
  audit call sites before moving.

#### S11. Claim empty banks `$77–$7f` / grow to 4 MB
*Escape valve · Low · both*

Not a saving, but the headroom that already exists. Banks `$77–$7f` (~147 KB) are
unassigned; new `SECTION "...", ROMX` fragments let the linker place data there,
and map `dba` pointers can target any bank. If even that fills, the MBC5 ROM-size
header can be raised to grow the file to 4 MB.

- **Files:** `contents/romx.link`, the rgbfix invocation in the `Makefile`.
- **Measure:** `prism-usage free` shows the empty banks today.
- **Risk:** none functionally; growing the file increases flashing/emulation
  size and may affect distribution patches.

---

## 4. Recommended sequencing

1. **S7 + S4** — clear dead/debug bytes first; trivial and unblocks tight banks.
2. **S10** — relieve bank 0; this is the constraint everything else trips over.
3. **S1** — the cry-fidelity pass; by far the largest single win, low code risk.
4. **S5, S3, S9** — lossless data compression/dedup; steady mid-size gains.
5. **S2 (lossy tier), S6, S8** — reserve for a deliberate pass when a specific
   bank is blocking, since they carry either art-quality or broad-refactor cost.
6. **S11** — fall back to the empty banks / 4 MB only after the cheap wins, so the
   ROM stays lean rather than merely larger.

> Validate every change with `prism-usage diff <before>.map <after>.map` and gate
> regressions with `prism-usage check --max-bank-usage 99` in a pre-commit hook.
