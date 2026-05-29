# Pokémon Prism — Codebase Overview

Pokémon Prism is a Game Boy Color ROM hack of Pokémon Crystal, built with the
[RGBDS](https://github.com/gbdev/rgbds) toolchain. The output is a 2MB `.gbc` ROM.
The codebase is ~100% Game Boy assembly (RGBASM dialect) with Python helpers for
graphics/audio preprocessing.

---

## Key Facts

| Property | Value |
|----------|-------|
| Target hardware | Game Boy Color |
| ROM size | 2 MB (128 × 16KB banks) |
| RGBDS version required | **0.7.0** (see [build.md](build.md)) |
| Output file | `pokeprism_nodebug.gbc` |
| Pokémon count | 260+ |
| Maps | 461 |
| ROM code banks | 31 (Code 1–31) |

---

## Top-Level Files

| File | Role |
|------|------|
| `main.asm` | Master include for all code; defines 31 ROMX "Code" sections |
| `home.asm` | ROM bank 0 runtime library; first code executed on boot |
| `audio.asm` | Music pointers, cry headers, SFX tables |
| `gfx.asm` | Graphics data includes (pics, sprites, tilesets, font) |
| `maps.asm` | Includes all 461 map definition files |
| `text.asm` | Pokédex entries and dialogue text blobs |
| `wram.asm` | Work RAM variable layout (includes `hram.asm`, `vram.asm`, `sram.asm`) |
| `includes.asm` | Included at the top of most .asm files; pulls in `constants.asm` + `macros.asm` |
| `constants.asm` | Includes all 38 constant definition files |
| `macros.asm` | Includes all 21 macro definition files |
| `gbhw.asm` | Game Boy hardware register definitions |
| `interrupts.asm` | VBlank and other interrupt handlers |
| `rst.asm` | Restart vectors ($00, $08, $10, …, $38) |
| `version.asm` | Build-date and version constants |

---

## Subsystem Map

```
pokeprism/
├── home/        ROM bank 0 library — bankswitch, joypad, LCD, scripting, math
├── engine/      Banked game logic — menus, Pokémon mechanics, overworld, UI
├── battle/      Battle engine — move effects, AI, animations, trainer HUDs
├── event/       Special events — minigames, gyms, story scripts
├── maps/        461 map files — warps, NPCs, scripts per location
├── data/        Tables — base stats, movesets, wild data, Pokédex entries
├── constants/   Numeric definitions — species IDs, move IDs, flags, etc.
├── macros/      Code-generation macros — enums, data structs, map helpers
├── audio/       Music tracks, SFX, DED-compressed cry data
├── gfx/         PNG source art → .2bpp/.1bpp after preprocessing
├── tilesets/    Map collision and tileset headers
├── trainers/    Trainer parties and class metadata
├── items/       Item attributes, descriptions, mart inventories
├── text/        (generated) compressed dialogue text
├── contents/    Linker scripts — bank allocation, memory sections
├── utils/       C build tools (scaninc, pokepic, lzcomp, rendergifs …)
└── patch/       IPS patch generation infrastructure
```

---

## ROM Bank Layout (high level)

The linker script `contents/romx.link` divides 117 banked ROM slots:

| Banks | Contents |
|-------|----------|
| $01–$12 | Code sections 1–18 (engine logic) |
| $13–$1f | Code sections 19–31 + specialised modules |
| $20–$35 | Map block data (per-map visual tiles) |
| $36–$44 | Map scripts (event handlers) |
| $45–$55 | Graphics (tilesets, overworld sprites, battle anims) |
| $56–$65 | Audio (music tracks) |
| $66–$75 | DED compressed cry audio (split across 27 sections) |

Bank 0 (`ROM0`) is reserved for `home/` — code that must be callable from any bank.

---

## Docs in This Folder

| File | Contents |
|------|----------|
| [build.md](build.md) | How to build the ROM, tool versions, troubleshooting |
| [codebase-map.md](codebase-map.md) | Per-directory file listing with one-line descriptions |
| [maps-and-events.md](maps-and-events.md) | Map file format, event scripting, warp/NPC definitions |
| [data-formats.md](data-formats.md) | Trainer parties, base stats, moves, items — struct layouts |
| [memory-layout.md](memory-layout.md) | WRAM/HRAM/SRAM/VRAM variable map, key addresses |
| [macros-and-constants.md](macros-and-constants.md) | Enum system, key macros, how constants.asm is organized |
