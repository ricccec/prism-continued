# Pokémon Prism — The Book

*A guided, book-length read through the Pokémon Prism codebase: from two megabytes of banked ROM up to the world you walk through, the battles you fight, and the tools that build it all.*

---

## What this is

Pokémon Prism is a Game Boy Color ROM hack of Pokémon Crystal, written almost entirely in RGBDS assembly with a handful of Python and C helpers for graphics, audio, and patching. It is a large, old-school codebase: no garbage collector, no heap, no test suite — just data tables, pointer indirection, small bytecode interpreters, and far-call trampolines, all running at 60 frames per second on hardware designed in 1998.

This book is a *narrative* tour of that codebase, written to be read front to back. It is not a reference manual — the `docs/` folder already has excellent references (see [Companion references](#companion-references) below). Instead, each chapter tells the story of one subsystem: what problem it solves, how the data is shaped, and how the engine reads it, grounded throughout in real, verified excerpts from the source with file paths cited so you can go read the originals.

The gold standard for tone is [`../map-rendering.md`](../map-rendering.md) and [`../overworld-maps-bedtime-read.md`](../overworld-maps-bedtime-read.md); this book extends that spirit across the whole project.

---

## How to read it

The eleven chapters fall into three movements:

- **Foundations (1–4)** — the artifact, its idioms, its memory, and its data. Read these first; every later chapter assumes them.
- **The Overworld (5–8)** — the heart of the book. How a map becomes a grid of pixels, how it's coloured and loaded, how scripts, warps, connections, NPCs, and encounters turn it into a living place, and the sixty-hertz loop that sets it all in motion.
- **Everything Else (9–11)** — the battle engine, the presentation layer (text, menus, audio, graphics), and the tooling you build and debug with.

You can read straight through, or jump to a chapter and follow its cross-references. A recurring theme runs the whole way: **data tables + pointer indirection + small VMs + far-call trampolines.** Once that pattern clicks, almost any file in the repo becomes legible.

---

## Table of contents

### Part I — Foundations

| # | Chapter | What it covers | Lines |
|---|---------|----------------|------:|
| 1 | [The Cartridge](01-the-cartridge.md) | What Prism is, GBC hardware constraints, MBC3 banking, the RGBDS 0.7.0 toolchain, how the 128-bank ROM is divided, and the `main.asm` / `home.asm` / `includes.asm` master include structure. | 229 |
| 2 | [Architecture & Idioms](02-architecture.md) | `home/` vs banked code, the `farcall`/`predef`/`rst` cross-bank call machinery, and the enum/macro/constant code-generation system that gives every ID one source of truth. | 328 |
| 3 | [The Memory Map](03-memory-map.md) | The GBC address space as Prism uses it: WRAM/HRAM/SRAM/VRAM regions, how `wram.asm` declares them, the key overworld buffers, and the save system (slots, checksums, recovery). | 350 |
| 4 | [Game Data](04-game-data.md) | The static content tables — base stats, evolutions and learnsets, TM/HM, moves, trainer parties, items, and wild encounters — and the macros that build each fixed-size record. | 393 |

### Part II — The Overworld

| # | Chapter | What it covers | Lines |
|---|---------|----------------|------:|
| 5 | [Anatomy of a Map](05-anatomy-of-a-map.md) | What a map *is* as data: the two-level header lookup, the block grid, and the tileset's three tables (metatiles, attributes, collision) that turn one byte into a 32×32-pixel block. | 503 |
| 6 | [Colour, Light & Loading](06-colour-and-loading.md) | How permission + time-of-day choose eight palettes, the dark-cave/Flash case and runtime fades, and the map-setup VM that assembles a live map step by ordered step. | 590 |
| 7 | [The Scripting VM & Events](07-scripting-and-events.md) | The climax: triggers and callbacks, the script bytecode VM, warps, seamless map connections and the scrolling camera, NPCs, runtime encounters, landmark signs — and a frame in the life of the overworld loop. | 827 |
| 8 | [The Overworld in Motion](08-overworld-in-motion.md) | The sixty-hertz loop that drives it all: smooth scrolling by streaming tiles into a screen-sized VRAM torus, the step state machines for player and NPCs, trigger detection underfoot, trainer line-of-sight, A-press interaction, hidden items, field moves, and the Start menu. | 737 |

### Part III — Everything Else

| # | Chapter | What it covers | Lines |
|---|---------|----------------|------:|
| 9 | [The Battle Engine](09-battle-engine.md) | Battle entry, the subsystem layout, the turn loop, move execution via effect-command bytecode, damage and type matchups, the animation interpreter, trainer AI, and battle end. | 369 |
| 10 | [Text, Menus, Audio & Graphics](10-text-menus-audio-gfx.md) | The presentation layer: the charmap and variable-width font, the menu driver and major screens, the audio driver and DED-compressed cries, and the PNG→2bpp→VRAM graphics pipeline. | 399 |
| 11 | [Tooling & Debugging](11-tooling-and-debugging.md) | The build (`make nodebug`), bank budgeting, the `utils/` C tools, the Python devtools, `DEBUG_MODE` and the in-game debug menus, the `/patch/` framework, and a closing epilogue. | 243 |

*Roughly 4,900 lines across eleven chapters.*

---

## Companion references

This book explains *how the systems work*. When you need *exact syntax to edit something*, reach for the reference docs alongside it:

| Doc | Use it for |
|-----|-----------|
| [`../overview.md`](../overview.md) | One-page project snapshot and subsystem map |
| [`../codebase-map.md`](../codebase-map.md) | Per-directory file listing — where does system X live? |
| [`../build.md`](../build.md) | Building the ROM, tool versions, troubleshooting |
| [`../maps-and-events.md`](../maps-and-events.md) | Map/warp/NPC/script macro syntax for editing |
| [`../data-formats.md`](../data-formats.md) | Exact struct layouts for stats, trainers, moves, items |
| [`../memory-layout.md`](../memory-layout.md) | Exhaustive WRAM/HRAM/SRAM/VRAM variable map |
| [`../macros-and-constants.md`](../macros-and-constants.md) | The enum system and key macros |
| [`../map-rendering.md`](../map-rendering.md) | The exact Python-level map render pipeline |
| [`../text-system.md`](../text-system.md) | Charmap, text macros, placeholder system |
| [`../debug-mode.md`](../debug-mode.md) | Debug menus, `DEBUG_MODE`, the patch framework |

---

Start with [Chapter 1 — The Cartridge](01-the-cartridge.md). Pour something warm. Let's go.
