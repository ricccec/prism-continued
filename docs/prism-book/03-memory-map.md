# Chapter 3 — The Memory Map

*Every byte of state the game can ever have lives in one of six named regions. Know which region holds what, and the code becomes readable almost by accident.*

---

## 3.1 The GBC Address Space at a Glance

The Game Boy Color CPU presents a 16-bit address space — 64 KiB, no exceptions. That space is divided by the hardware into fixed windows, each serving a distinct purpose. Before reading any source file that touches memory, this map is worth committing to muscle memory:

| Range | Region | What lives here in Prism |
|-------|--------|--------------------------|
| `$0000–$3FFF` | ROM0 | `home/` — always-mapped library, interrupt vectors, `rst` trampolines |
| `$4000–$7FFF` | ROMX | One of 117 switchable ROM banks — `engine/`, `battle/`, `data/`, maps |
| `$8000–$9FFF` | VRAM | Tile graphics, BG/window tile maps (2 banks on GBC) |
| `$A000–$BFFF` | SRAM | Battery-backed save RAM (4 banks) |
| `$C000–$CFFF` | WRAM0 | Fixed work RAM — stack, audio driver, overworld buffer, sprite table |
| `$D000–$DFFF` | WRAMX | Banked work RAM (7 banks, GBC only) — player data, map state, event flags |
| `$FE00–$FE9F` | OAM | Sprite attribute table (40 sprites × 4 bytes) |
| `$FF00–$FF7F` | I/O registers | Hardware control — LCD, joypad, timers, sound (`gbhw.asm`) |
| `$FF80–$FFFE` | HRAM | High RAM — `ldh`-accessible variables, DMA trampoline |

[Chapter 2](02-architecture.md) explains why ROM is banked and how `farcall` navigates the ROM window. This chapter is about the RAM side of that picture.

---

## 3.2 How the Codebase Declares Memory

Prism does not scatter `ds` directives across individual source files. All runtime memory is declared in one place: `wram.asm` at the repo root. That file opens with two includes:

```asm
; wram.asm
INCLUDE "includes.asm"
INCLUDE "macros/wram.asm"
INCLUDE "hram.asm"
INCLUDE "vram.asm"
```

`hram.asm`, `vram.asm`, and (at the very bottom) `sram.asm` are pulled in as children. The result is a single translation unit that the assembler processes to produce every address label for every RAM region in the game. If you want to know where a variable lives, there is exactly one file to search.

`macros/wram.asm` provides the struct-builder macros: `party_struct`, `box_struct`, `battle_struct`, `object_struct`, `channel_struct`, and about a dozen others. These emit contiguous `db`/`ds`/`dw` reservations under compound label prefixes, so `wPartyMon1HP` is literally `wPartyMon1` + offset, all computed by the assembler. The macro layer keeps the struct layout readable without any padding arithmetic on your part.

### The linker assigns banks

`wram.asm` declares sections using `SECTION "Name", WRAM0` or `SECTION "Name", WRAMX`. The linker script `contents/wram.link` assigns each section to its bank:

```
WRAM0
    "Version check"
    "Stack"
    "Audio WRAM"
    "WRAM 0"
    "Sprites WRAM"
    "Tilemap"
    "Battle"
    "Overworld Map"
    org $cd20
    "WRAM 0 continued"

WRAMX 1   org $d000 "WRAM 1"
WRAMX 2   "WRAM 2 aligned"  "WRAM 2 extra"  "Sound Stack"
WRAMX 3   "Metatiles"
WRAMX 4   "Attributes"
WRAMX 5   "GBC Video"  "LY Overrides"  "Collisions + ..."  "Palettes 2"
WRAMX 6   "WRAM 6"
WRAMX 7   "WRAM 7"
```

The `org` directives pin a few sections to fixed addresses where the engine needs to know them at compile time. Everything else fills in sequentially.

Switching the active WRAM bank is done by writing a value 1–7 to `rSVBK` (`$FF70`). The codebase wraps this in the `wbk` macro and its partner `sbk` for SRAM. You will see `wbk BANK(wDecompressedMetatiles)` before any code that touches metatile data, for instance.

---

## 3.3 WRAM0 — The Fixed Bank

`$C000–$CFFF` is always mapped. Everything here is reachable with a plain two-byte `ld hl, addr` — no bank switch needed — which makes it the right home for variables touched from ROM0 or from multiple different ROMX banks.

The layout, roughly:

| Approx. range | Contents |
|---------------|----------|
| `$C000–$C0FF` | Call stack (256 bytes) |
| `$C100–$C2C0` | Audio driver — 8 channel structs (`wChannel1`–`wChannel8`), volume, music ID |
| `$C300–$C3B5` | Sprite animation structs (10 × 16-byte records) |
| `$C3C5–$C3FF` | Text engine temporaries, script state pointers |
| `$C400–$C4FF` | OAM shadow — `wSprites`, 40 × 4 bytes |
| `$C4A0–$C51F` | `wTileMap` — 20 × 18 tilemap (360 bytes) |
| `$C608–$C7FF` | Battle WRAM union (party temp, battle structs, Hall of Fame temp) |
| `$C800–$CCFF` | `wOverworldMap` — 1300-byte block-grid buffer |
| `$CD20–$CFFF` | BG map tile buffer, attribute map, tile animation buffer |

`wOverworldMap` at `$C800` is the heart of the overworld renderer. It is a 1300-byte flat buffer — larger than any single map — that holds the current map's block grid plus a 3-block border on each side filled from neighboring maps. [Chapter 5](05-anatomy-of-a-map.md) covers the block-grid format and how `ChangeMap` decompresses data into this buffer.

`wTileMap` at `$C4A0` is the software shadow of the hardware BG tile map: a 20×18 grid of 8-bit tile indices that the engine writes during scroll updates and copies to VRAM during VBlank.

The OAM shadow `wSprites` at `$C400` holds 40 sprite records (Y, X, tile index, attribute flags). `PushOAM` in `home/video.asm` triggers a DMA transfer of this 160-byte block into hardware OAM at `$FE00–$FE9F`, initiated via a small routine copied into HRAM at startup.

---

## 3.4 WRAMX — The Banked Banks

The GBC adds seven switchable WRAM banks (`$D000–$DFFF`, banks 1–7). Prism uses all seven, with clearly delineated roles:

### Bank 1 — Game state

This is where most of the mutable game state lives. WRAM bank 1 is the longest section declaration in `wram.asm`, spanning roughly lines 1453–3031. It is always mapped when the overworld or battle engine is running. Key regions within it:

**`wOverworldMapAnchor` (`$D194`)** — a pointer into `wOverworldMap` indicating where the camera is currently anchored.

**`wMapHeader` (`$D19D`)** — a 12-byte copy of the current map's secondary header (border block, width, height, block-data bank/pointer, script-header bank/pointer, event-header pointer, connection bitmask). This is the runtime working copy; the ROM original is accessed through `CopySecondMapHeader`.

**`wTimeOfDay` (`$D269`)** — a single byte encoding the current time-of-day slot (morning, day, evening, night). Used by the palette system and NPC scheduling.

**`wObjectStructs` (`$D4D6`)** — an array of 13 fixed-size sprite state records (player + 12 NPCs), each 56 bytes, laid out by the `object_struct` macro. Each record tracks the sprite tile, movement type, direction, facing, step duration, current and last map coordinates, and OAM offset. `wObjectStructsEnd` is at `$D6DE`.

**`wMapObjects` (`$D71E`)** — the raw NPC/event table copied from the map event header. `wObject1Object` through `wObject16Object` are 16 fixed-size records describing each NPC's sprite ID, coordinates, movement pattern, hour of availability, and event script pointer.

**`wTimeOfDayPal` (`$D841`)** and the palette buffers — 8 × 4-color BG palettes cached in WRAM for the time-of-day fade system. Chapter 6 covers these in full.

**`wEventFlags` (`$DA72`)** — the flat bit array of every event flag in the game. The `flag_array NUM_EVENTS` macro reserves `(NUM_EVENTS + 7) / 8` bytes. `wEventFlags` is the single most-queried variable in the scripting engine; `FlagAction` and `EventFlagAction` (via `predef`) set and test individual bits by index.

**`wPlayerData` (`$D47B`)** — player identity, name, rival name, Prism-specific skill levels (mining, smelting, etc.), and badge flags for both Naljo and Rijon. `wPlayerDataEnd` marks the boundary. The save engine copies this entire span verbatim to `sPlayerData` in SRAM.

**`wMapData` (`$DCA8`)** — map metadata that persists across warp transitions: dig warp, backup warp, spawn point, current map group/number (`wMapGroup`/`wMapNumber` at `$DCB5`/`$DCB6`), player coordinates (`wYCoord`/`wXCoord`).

**`wPokemonData` (`$DD00` area)** — party, current-box Pokémon, pokedex caught/seen arrays, bag inventory.

**Script state** — `wScriptFlags` (`$D434`), `wScriptFlags2`, `wScriptFlags3`, `wScriptBank`, `wScriptPos`, `wScriptStack`. These are the registers and call stack of the scripting VM described in Chapter 7.

**Script var stack** — `wScriptVarStack` in WRAM bank 2 (`$D000` range of bank 2): a 15-deep stack for the `s_pushvar`/`s_popvar` script commands, plus `wExtraData` which carries data not included in the main checksum unless the save format is new enough.

### Bank 3 — Metatiles

```asm
; wram.asm
SECTION "Metatiles", WRAMX
wDecompressedMetatiles::
    ds 256 * 16
```

4096 bytes. One entry per block ID (0–255), each entry 16 bytes encoding the 4×4 grid of tile indices that make up the block. Populated by `LoadMetatilesTilecoll`.

### Bank 4 — Attributes

```asm
SECTION "Attributes", WRAMX
wDecompressedAttributes::
    ds 256 * 16
```

Same shape as the metatile table. Each byte is a CGB palette slot index (0–7) for the corresponding tile within the block. The palette slot tells the renderer which of the 8 active BG palettes to use for that tile.

### Bank 5 — Collision, GBC Video, Palette Buffers

```asm
SECTION UNION "Collisions + ...", WRAMX
wDecompressedCollision::
    ds 256 * 4
```

1024 bytes. Four bytes per block ID — one per 2×2-tile quadrant. Each byte is a collision constant from `constants/collision_constants.asm`. This is what `GetCoordTile` reads after indexing through `wOverworldMap`.

Bank 5 also holds `wOriginalBGPals`/`wBGPals`/`wOBPals` (eight 4-color palettes each, 8 × 4 × 2 = 64 bytes per set), the LY-override tables for mid-scanline palette tricks, and `wLYOverridesBackup`. Multiple of these sections overlap via `SECTION UNION` — the collision table, battle animation buffers, and palette data reuse the same physical bytes at different times.

### Bank 6 — Decompress Scratch

```asm
SECTION "WRAM 6", WRAMX
wDecompressScratch::  ds $400
wDecompressScratch2:: ds $800
wBackupAttrMap::      ds $400
```

A 4 KiB scratch space. `FarDecompressAtB_D000` in `home/decompress.asm` decompresses LZ-compressed data here before the caller copies it to its final destination. When `ChangeMap` calls `FarDecompressAtB_D000` with the block-grid data, the decompressed bytes land in `wDecompressScratch` and are then copied row-by-row into `wOverworldMap`. This indirection keeps `wOverworldMap` (in WRAM0) intact until the full new map is ready.

### Bank 7 — Window Stack

```asm
SECTION "WRAM 7", WRAMX
wWindowStack:: ds $1000 - 1
wWindowStackBottom:: ds 1
```

A nearly full 4 KiB window for the menu/dialog windowing system.

---

## 3.5 VRAM — Two Banks of Tile Data

VRAM occupies `$8000–$9FFF`. On GBC, the hardware supports two banks:

```asm
; vram.asm
SECTION "VRAM0", VRAM, BANK [0]
vObjTiles::  ds $800    ; $8000 battle/menu sprites
vFontTiles:: ds $800    ; $8800 font
vBGTiles::   ds $800    ; $9000 overworld background tiles
vBGMap::     ds $400    ; $9800 BG tile map
vWindowMap:: ds $400    ; $9c00 window tile map

SECTION "VRAM1", VRAM, BANK [1]
vStandingFrameTiles:: ds $800
vWalkingFrameTiles::  ds $800
vBGTiles2::           ds $800
vBGAttrs::            ds $400   ; $9800 bank 1: BG attribute map
vWindowAttrs::        ds $400   ; $9c00 bank 1: window attribute map
```

Each 8×8-pixel tile occupies 16 bytes in 2bpp format (two bit-planes, 2 bits per pixel, 4 color values). VRAM bank 0 holds the tile pixel data; VRAM bank 1's tile-map region (`$9800–$9FFF`) holds the GBC attribute bytes — palette ID, VRAM bank selector, flip flags — that correspond to each tile-map position. The LCD hardware reads both banks simultaneously during rendering.

VRAM can only be written when the screen is off or during HBlank/VBlank. All VRAM writes in the engine are gated behind `hVBlank` flags or a `DisableLCD`/`EnableLCD` bracketing in the map-setup sequence.

---

## 3.6 HRAM — Twelve Bytes That Run the World

HRAM is `$FF80–$FFFE`, 127 bytes. The Game Boy's `ldh a, [$FFxx]` instruction is one byte shorter and one cycle faster than `ld a, [$FFxx]` — a meaningful saving in tight loops and interrupt handlers. The VBlank interrupt handler runs hundreds of times per second; every cycle it spends on overhead is a cycle stolen from gameplay logic.

`hram.asm` fills these 127 bytes almost completely. A tour of the most load-bearing inhabitants:

**`hROMBank` (`$FF9B`)** — a shadow of the currently-mapped ROM bank. The far-call trampoline (`home/farcall.asm`) reads this before every cross-bank call to know what bank to restore on return. Without this shadow the engine would have to re-read the MBC register, which is not directly readable on the MBC3.

**`hMapEntryMethod` (`$FF9D`)** — how the player entered the current map: walked through a connection, used a warp, used Fly, used Dig, and so on. The map-setup sequence branches on this to decide whether to play an entry animation.

**`hSCX` / `hSCY` (`$FFD3`/`$FFD4`)** — WRAM shadows of the hardware scroll registers `rSCX`/`rSCY`. The engine updates these during scroll calculations, then copies them to the hardware registers during VBlank to keep the scroll synchronized to the tile-map update.

**`hBGMapUpdate` / `hOAMUpdate`** — single-byte flags that tell the VBlank handler whether to run `UpdateBGMapBuffer` or `PushOAM` on the current frame. Setting a flag in game logic and doing the actual copy in VBlank keeps VRAM writes in the safe window.

**`hPushOAM`** — five bytes that hold a short machine-code routine copied from ROM into HRAM at startup. The Game Boy's OAM DMA transfer (`rDMA`) requires the CPU to halt in HRAM for 160 microseconds while 160 bytes are copied from a WRAM page into OAM. The routine is small enough to fit in HRAM and stays there permanently:

```asm
; home/video.asm
ForcePushOAM:
    lb bc, 40 + 1, rDMA & $ff
    ld a, HIGH(wSprites)       ; high byte of source address
    jp hPushOAM                ; jump into the HRAM stub
```

`hPushOAM` holds the `ld [$ff46], a` / `ld b, 40` / `dec b` / `jr nz` loop that must execute from HRAM. Calling `PushOAM` in VBlank copies the 160-byte `wSprites` shadow into hardware OAM for every frame.

**`hPredefTemp` / `hBuffer` / `hFarCallSavedA`** — temporaries used by the `farcall` trampoline to save and restore registers across bank switches. Because these are in HRAM, the trampoline itself can use fast `ldh` instructions for every save/restore operation.

**`hScriptVar` / `hScriptHalfwordVar`** — a 1-byte and a 2-byte variable used as output registers for scripting engine commands. When a script command returns a value (a flag test result, a dialog choice index, a computed number), it stores it here for the next command to read.

---

## 3.7 The Save System — SRAM, Blocks, and Checksums

SRAM lives at `$A000–$BFFF` and is battery-backed. The linker assigns four SRAM banks via `contents/sram.link`:

| Bank | Contents |
|------|----------|
| 0 | Scratch tiles, Battle Tower party backup, build number, RTC data, backup save |
| 1 | Primary save: options, `sGameData` (player + map + Pokémon), `sExtraData`, checksums, current box |
| 2 | PC boxes 1–7 |
| 3 | PC boxes 8–14 |

`sram.asm` declares the layout using the same size-mirror pattern seen throughout the codebase: `sPlayerData:: ds wPlayerDataEnd - wPlayerData`. The SRAM region exactly mirrors the WRAM region it is meant to hold. When the save engine calls `SavePlayerData` it copies `bc = wPlayerDataEnd - wPlayerData` bytes from `wPlayerData` to `sPlayerData` using `rst CopyBytes` — no size constant needed, the assembler computes it.

### The primary/backup pair

SRAM bank 0 holds a **backup save** that mirrors the primary (bank 1). Every time the game writes the primary save, it also writes the backup. The two save slots use `sValidCheck1`/`sValidCheck2` and `sBackupValidCheck1`/`sBackupValidCheck2` as sentinel bytes:

```asm
; engine/save.asm
ValidateSave:
    sbk BANK(sValidCheck1)
    ld a, 99
    ld [sValidCheck1], a
    ld a, " "           ; $20
    ld [sValidCheck2], a
```

`sValidCheck1` is set to `99` and `sValidCheck2` to `$20` (space). A save with any other values in those positions is considered corrupt.

### The checksum

`Checksum` in `engine/save.asm` walks a byte range and accumulates a 16-bit running sum in `de`:

```asm
; engine/save.asm
Checksum:
    ld de, 0
    inc b
    inc c
    jr .ok
.loop
    ld a, [hli]
    add e
    ld e, a
    adc d
    sub e
    ld d, a
.ok
    dec c
    jr nz, .loop
    dec b
    jr nz, .loop
    ret
```

The `adc d / sub e` pattern computes the carry from the 8-bit addition and adds it to `d` without a separate carry flag — it is the standard GB 16-bit accumulator pattern. The result in `de` is written to `sChecksum` (2 bytes) after checksumming `sGameData`. A separate `sExtraChecksum` covers `sExtraData`.

`SaveChecksum` computes and stores both checksums. `VerifyChecksum` recomputes them and compares. `TryLoadSaveFile` orchestrates the full load path:

1. Call `VerifyChecksum`. If it passes, load from primary save, rebuild backup.
2. If primary fails, call `VerifyBackupChecksum`. If it passes, load from backup, rebuild primary, display a warning.
3. If both fail, display a "save file is corrupted" message and refuse to load.

This primary/backup architecture means a power interruption during a save write corrupts at most one of the two slots, and the game can always recover from the other.

### SRAM access discipline

SRAM is off by default. The `sbk` macro (short for "switch SRAM bank and enable") writes the bank to `rRAMB` and also writes the unlock sequence to the MBC3's RAM-enable register. `CloseSRAM` writes zero to disable SRAM again. Most save functions end with `jp CloseSRAM` — locking SRAM is cheap and protects against stray writes.

---

## 3.8 Key Variables at a Glance

The table below maps the overworld/map concepts from other chapters to their WRAM addresses. These appear constantly in the source.

| Symbol | Address | Size | What it holds |
|--------|---------|------|---------------|
| `wOverworldMap` | `$C800` | 1300 B | Block-grid buffer (WRAM0) |
| `wMapGroup` | `$DCB5` | 1 B | Current map group |
| `wMapNumber` | `$DCB6` | 1 B | Current map number |
| `wYCoord` / `wXCoord` | `$DCB7` / `$DCB8` | 1 B each | Player position in blocks |
| `wObjectStructs` | `$D4D6` | 13 × 56 B | Sprite state (player + 12 NPCs) |
| `wMapObjects` | `$D71E` | variable | NPC/event table for current map |
| `wDecompressedMetatiles` | WRAM bank 3 | 4096 B | Block-ID → tile-IDs lookup |
| `wDecompressedAttributes` | WRAM bank 4 | 4096 B | Block-ID → palette-slots lookup |
| `wDecompressedCollision` | WRAM bank 5 | 1024 B | Block-ID → quadrant collision bytes |
| `wDecompressScratch` | WRAM bank 6 | 1024 B | LZ decompression workspace |
| `wEventFlags` | `$DA72` | ~100 B | Bit array of all event flags |
| `wScriptBank` / `wScriptPos` | `$D439` / `$D43A` | 1 + 2 B | Script VM program counter |
| `wTimeOfDay` | `$D269` | 1 B | Current time-of-day slot |
| `hROMBank` | `$FF9B` | 1 B | Currently-mapped ROM bank shadow |
| `hMapEntryMethod` | `$FF9D` | 1 B | How player arrived on this map |
| `hSCX` / `hSCY` | HRAM | 1 B each | Scroll register shadows |

For the full variable inventory — every named label with a description — see `docs/memory-layout.md`.

---

## Where to Next

You now have a spatial model of the entire runtime: which bytes are always accessible, which require a bank switch, which survive a power cycle, and how the save system ensures at least one valid copy exists at all times. The address ranges introduced here will appear as plain facts in the chapters that follow, without re-explanation.

[Chapter 4 — Game Data](04-game-data.md) moves into ROM, examining how Pokémon stats, moves, items, and trainer records are laid out as fixed-size binary tables and how the engine indexes into them at runtime.
