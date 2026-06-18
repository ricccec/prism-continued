# Chapter 11 — Tooling & Debugging

*The ROM is the output. The build system, the linker map, and the debug menus are the instruments you use to understand it.*

---

## The Build

Every change to Pokémon Prism ends with the same command:

```bash
make nodebug RGBDS="/path/to/rgbds-0.7.0/"
```

That single invocation does a remarkable amount of work. Before it touches a single `.asm` file, Make compiles every C tool in `utils/` — `scaninc`, `bankends`, `bspcomp`, `pokepic`, `lzcomp`, `ipspatch`, `gbspatch`, `gbstrim`, `pngtrim`, `qrconv`, `rendergifs`. It then converts graphics, compresses assets, assembles six translation units, links them, and fixes the cartridge header. The whole process takes a few seconds on modern hardware.

### RGBDS 0.7.0 — the version lock

As Chapter 1 introduced, the version lock is non-negotiable. The codebase uses ~427 symbol assignments in the pre-`DEF` syntax (`sym EQU value`, `sym = value`). RGBDS 0.8 deprecated the pattern and produced warnings; 1.0 removed support entirely. RGBDS 0.7.0 is the last version that accepts the syntax silently. The `RGBDS` variable provides a path prefix with a trailing slash so the Makefile can prefix all four tools (`rgbasm`, `rgblink`, `rgbfix`, `rgbgfx`) uniformly:

```makefile
# Makefile:37-41
RGBDS ?=
RGBASM  ?= ${RGBDS}rgbasm
RGBFIX  ?= ${RGBDS}rgbfix
RGBLINK ?= ${RGBDS}rgblink
RGBGFX  ?= ${RGBDS}rgbgfx
```

If you have 0.7.0 on your `$PATH`, you can omit the variable entirely. If you built it locally under `~/rgbds-0.7.0/`, pass `RGBDS="$HOME/rgbds-0.7.0/"` (trailing slash required).

### Build targets

| Target | Output | Notes |
|--------|--------|-------|
| `make nodebug` | `pokeprism_nodebug.gbc` | Release ROM — the starting point for most work |
| `make prism` | `pokeprism.gbc` | Debug ROM — adds `-DDEBUG_MODE` to all assembly flags |
| `make all` | both ROMs + GBS + freespace report | Default comprehensive build |
| `make gbs` | `pokeprism.gbs` | Music-only export for GBS players |
| `make patch` | `pokeprism.bsp` / `_*.ips` | Binary patch files (requires `baserom.gbc`) |
| `make freespace` | `contents/bank_ends.txt` | Per-bank free-byte report |
| `make genimages` | GIF previews in `maps/` | Map visual previews via `rendergifs` |
| `make clean` | — | Remove all generated files |
| `make tidy` | — | Remove ROMs and object files only |

`make nodebug` produces three files in the project root: `pokeprism_nodebug.gbc` (the 2 MB ROM), `pokeprism_nodebug.sym` (full symbol table for use in emulator debuggers), and `pokeprism_nodebug.map` (the complete linker map).

### Dependency tracking: `scaninc`

The Makefile knows which `.asm` files each object depends on because of `utils/scaninc`. The build calls it at rule-evaluation time:

```makefile
# Makefile:121-123
preinclude_deps := includes.asm $(shell utils/scaninc includes.asm)

$1: $2 $$(shell utils/scaninc $2) $(preinclude_deps)
```

`scaninc` walks a source file's `INCLUDE` directives recursively and prints every transitively included file to stdout. Make inserts that list as extra prerequisites for the object rule — so editing a deeply nested constant file or macro causes only the affected objects to rebuild, not everything. Without `scaninc`, you'd have to `make clean` every time you touched a shared header.

### The pipeline in detail

Six translation units are assembled with `rgbasm` (one each for `audio.asm`, `gfx.asm`, `main.asm`, `maps.asm`, `text.asm`, and `wram.asm`). `rgblink` then combines them using `contents/contents.link`, which includes the bank-placement scripts described in Chapter 1. Finally, `rgbfix` stamps the Game Boy cartridge header: title, CGB flag, MBC type, ROM/RAM sizes, and checksums.

The debug build differs in one flag:

```makefile
# Makefile:104-105
$(pokeprism_obj):         RGBASMFLAGS += -DDEBUG_MODE
$(pokeprism_nodebug_obj): RGBASMFLAGS +=
```

Both ROMs share the same SRAM layout, so a `.sav` file is interchangeable between them.

---

## Bank Budgeting

### The linker map

`pokeprism_nodebug.map` is a plain-text file written by `rgblink` that lists every section: its bank, its start address, its length, and all the symbols within it. It is the authoritative record of where everything landed after linking.

`utils/bankends` reads it and prints the final address of the last section in each ROMX bank, annotated with the number of bytes remaining until the bank ceiling (`$8000`):

```
Bank $00: $3cc7 ($0339)   ← 825 bytes free in ROM0
Bank $0e: $7ff9 ($0007)   ← 7 bytes free — nearly full
Bank $0f: $7cb1 ($034f)   ← 847 bytes free
```

The format — end address and free bytes in parentheses — is produced by parsing the `.map` file in `utils/bankends.c` and walking the section list to find the highest address per bank.

### `make freespace` and `contents/bank_ends.txt`

Running `make freespace` (or `make all`, which includes it) writes this report to `contents/bank_ends.txt`:

```makefile
# Makefile:146-147
contents/bank_ends.txt: prism
    utils/bankends pokeprism.map > $@
```

Note that `freespace` depends on the debug ROM (`prism`), not `nodebug`. The debug build is slightly larger — its extra code shifts a handful of section boundaries — so it gives the more conservative (smaller) free-space figure. You add code budget against the debug ROM and the release build is guaranteed to fit.

### Why free space matters

The ROM is exactly 2,097,152 bytes — 128 × 16 KB banks. The linker script in `contents/romx.link` assigns each named section to a specific bank. If a section overflows its bank, `rgblink` dies with an error. There is no automatic overflow: the hardware window is 16 KB and the linker script is explicit.

As documented in `docs/map-rom-budget.md`, only ~28,254 bytes of ROMX remain globally at the time of writing, and bank fragmentation means the useful supply is uneven — bank `$0e` has 7 bytes free; bank `$0f` has 847. When you add a new map, NPC dialogue, or battle animation, you check `bank_ends.txt` before choosing which `SECTION` to append to, or whether to open a new one in a bank with headroom.

The `docs/map-rom-budget.md` analysis quantifies the cost of a typical map addition at roughly 300–580 bytes compiled — block data, script, headers, and events combined. At that rate the global budget supports a few dozen more average maps before requiring either a data-format compression improvement or retiring dead sections.

---

## The C Build Tools (`utils/`)

The C programs in `utils/` are compiled by `make -C utils/` before any assembly work begins. They are small, purpose-built, and worth understanding individually.

| Binary | Source | Purpose |
|--------|--------|---------|
| `scaninc` | `scaninc.c` | Walk `INCLUDE` directives recursively; emit dependency list for Make |
| `pokepic` | `pokepic.c` | Convert a Pokémon PNG framesheet into `.2bpp` tile data, `.pal` colour table, and `frames.asm` sprite layout |
| `lzcomp` | `lz/` submodule | Multi-pass LZ compressor; tries all 96 method variants and emits the shortest result |
| `bankends` | `bankends.c` | Parse the linker `.map` and print free bytes per ROM bank |
| `rendergifs` | `rendergifs.c` | Render map block data to GIF image previews (`make genimages`) |
| `ipspatch` | `ipspatch.c` | Create or apply IPS patches (binary diffs between two ROMs) |
| `gbspatch` | `gbspatch.c` | Patch GBS offset table into the release ROM for music export |
| `gbstrim` | `gbstrim.c` | Trim a GBS file to the correct length after patching |
| `bspcomp` | `bsp/` submodule | BSP patch creation and application (the save-migration patcher) |
| `qrconv` | `qrconv.c` | Convert a QR ASM descriptor into `.1bpp` tile data for in-game QR codes |
| `pngtrim` | `pngtrim.c` | Strip trailing transparent rows from PNGs before tile conversion |
| `asm2bin.sh` | shell | Assemble a standalone `.asm` file to a raw binary |
| `coll2bin.sh` | shell | Compile collision data from source to binary |

`lzcomp` deserves a mention beyond its table entry. Chapter 6 described how map block data is LZ-compressed before inclusion, and `docs/map-rom-budget.md` reports a 37% overall reduction (71 KB raw → 45 KB compressed). `lzcomp` achieves near-optimal results by trying every one of the format's seven command types — literal copy, byte repeat, pair repeat, zero fill, and three back-reference variants — across all parameter combinations and selecting the shortest. The Makefile rule that invokes it is a simple catch-all:

```makefile
# Makefile:211
%.lz: %
    utils/lzcomp -- $< $@
```

---

## Python Devtools (`prism-dev`)

The Python devtools live in a separate repository, `pokeprism-devtools`, and are installed with `pipx install -e <path-to-clone>`. They expose two commands:

- **`prism-sym`** — symbol lookup. Given a label name or a ROM address, it returns the matching entry from `pokeprism_nodebug.sym`. Useful for quickly answering "what address does `OverworldLoop` land at?" or "what symbol is at bank 5, address `$5A10`?"

- **`prism-dev`** — the development server and start-state tool. Its primary job is to patch a `.sav` file to a known state (player position, party, items, event flags) and launch SameBoy at exactly that state, without rebuilding the ROM. The TUI (`tools/start-state/tui.py`, driven by `questionary`) lets you edit the state interactively, watch the `.sym` file for changes on rebuild, and hot-restart the emulator. This is the tool to reach for when you are iterating on a specific room or event — define a `state.json` once, and every `make nodebug` → `prism-dev` cycle drops you directly back into the scene you're working on.

The supporting library in `tools/_lib/` provides standalone (stdlib-only) parsers for `.sym` files, constants, map headers, save files, LZ-compressed data, block data, and person events. `tools/test_lib.py` smoke-tests these parsers against the real `.sym` and constant files on every run, catching regressions in the parsers themselves.

The `prism-mapview` tool (also in the devtools repo) renders a full-colour PNG of any map using the same data pipeline the game uses — block grid → metatile expansion → 2BPP tiles → CGB palette — documented in `docs/map-rendering.md`. It is useful for reviewing a map edit before loading the ROM.

---

## Debug Mode

### The build flag

The debug ROM is built with `-DDEBUG_MODE` passed to `rgbasm` for every object. The codebase uses a one-byte macro to branch on it without shifting addresses between the two builds (`macros.asm:327-335`):

```asm
MACRO debug_mode_flag
    if DEF(DEBUG_MODE)
        scf       ; set carry → "debug is on"
    else
        and a     ; clear carry → "debug is off"
    endc
ENDM
```

The macro emits a single byte either way, so section sizes are identical in both builds — a subtle but important constraint. If debug-gated code were surrounded by `IF/ENDC` guards that changed section lengths, every address after the guard would differ between builds, and `.sym` files would cross-contaminate.

Larger blocks — entire functions, menu entries, map warps — use `IF DEF(DEBUG_MODE) ... ENDC` directly. Files gating code this way include `engine/main_menu.asm`, `engine/startmenu.asm`, and `maps/BattleTowerEntrance.asm`. `grep -rln DEBUG_MODE` will enumerate them all.

### The two debug menus

There are two separate debug menus. They serve different purposes.

**Main-menu Debug Options** (`engine/main_menu_debug.asm`) appears as the fourth option on the title screen when running the debug ROM. It is a recovery tool for the save file, not dependent on a valid existing save. Three options: reset the RTC so the game re-asks for the date, erase all four SRAM banks, or overwrite the build-number field to bypass the save-incompatibility check.

**Overworld Debug Menu** (`engine/debug_menu.asm`, `engine/debug_menu_contents.asm`) is opened from the in-game Start menu → **Debug**. It operates on live WRAM and takes effect immediately:

| Option | Capability |
|--------|-----------|
| Get #mon | Spawn any species at any level (1–100) with an optional held item |
| Manage Items | Add arbitrary items; manage TMs/HMs |
| Manage Money | Edit trainer ID, money, coins |
| Warp Anywhere | Pick any map by ID and teleport |
| Edit flags | Toggle engine and event flags (fly-unlock, story progression) |
| Memory Access | Read/write arbitrary WRAM addresses; jump to arbitrary ROM addresses |
| Miscellaneous | Sound test, stopwatch, exp-group test, credits roll |
| Pics | Cycle through every trainer class or Pokémon species sprite |

Submenus are declared with a compact DSL in `macros/debug_menu.asm`:

```asm
ExampleMenu: debug_menu " Title", ParentMenu, .options, DefaultAction, LoadAction
.options debug_menu_options .a, .b, .c
.a debug_option "Label A", ActionLabelA
.b debug_option "Label B", ActionLabelB, CursorHandlerB, SelectHandlerB
.c debug_option "Back", DebugMenuCancel
```

Adding a new debug option is a matter of appending a `debug_option` line and writing its action routine. The DSL handles cursor movement, the selection highlight, and the L/R navigation handlers.

### The `/patch/` bspcomp framework

`make patch` compiles `patch/patch.txt` using `utils/bspcomp` into `pokeprism.bsp` — a binary patch that, when applied to a vanilla Pokémon Crystal 1.1 ROM, produces the Prism ROM. The Makefile asserts the Crystal ROM's SHA1 before applying (`Makefile:160-162`).

The more interesting use of the framework is save-file migration. When a player loads a save from an older build, `patch/save_patches.txt` runs a sequence of in-place SRAM fix-ups: resetting RTC state, repairing a broken TM slot, correcting party data. This is how the team ships breaking changes to the save format without corrupting players' existing files. The entire migration system is expressed in the bspcomp DSL — a small scripting language whose arithmetic and branching primitives are documented inline across the files in `patch/`.

---

## A Practical Change Workflow

There is no automated test suite. Correctness is verified by building and running the ROM. A typical iteration cycle looks like this:

1. **Edit** the source file — script, map, data table, engine routine.
2. **Build**: `make nodebug RGBDS="/path/to/rgbds-0.7.0/"`. If the build fails, `rgbasm` prints the file and line number; bank overflow errors from `rgblink` name the overfull section.
3. **Check the budget** (if you added data): `make freespace` updates `contents/bank_ends.txt`. Find your bank in the file and verify the free-byte count is still positive.
4. **Run** `pokeprism_nodebug.gbc` in SameBoy (or any accurate GBC emulator). Load a save or use `prism-dev` to drop into the affected scene immediately.
5. **Observe** — did the NPC say the right thing, did the warp land correctly, did the battle animation play? SameBoy's debugger can load the `.sym` file and let you set breakpoints by label name.
6. **Iterate** — for complex bugs, build the debug ROM (`make prism`) and use the in-game Memory Access menu to inspect live WRAM, or the Warp Anywhere option to reproduce the broken state quickly.

The feedback loop is fast because the build is fast: a full `make nodebug` from clean takes a few seconds; incremental rebuilds after a single file change are nearly instant thanks to `scaninc`'s precise dependency tracking.

---

## Epilogue

We started in Chapter 1 with the hardware: a 4 MHz Sharp SM83, a 16-bit address bus, and a 2 MB ROM parcelled into 128 × 16 KB banks. We end here with build scripts, linker maps, and in-game cheat menus. Between those endpoints the book has touched the memory map, game data tables, map rendering, the scripting VM, the battle engine, the text system, audio, and the graphics pipeline. Standing back, the view is consistent across all of it.

Every system in Pokémon Prism is a variation on the same handful of ideas. A piece of data goes into a fixed-size record in a flat table. A pointer in a second table points to it by index. A routine in ROM0 dispatches to a banked handler through a far-call trampoline. The handler runs a small VM — the scripting interpreter, the battle command dispatch, the debug menu loop, the audio sequencer — ticking at 60 frames per second and consuming a few hundred bytes of WRAM. When the VM needs a resource it cannot hold in registers, it reads a pointer, switches banks, reads the data, switches back. The whole program is this loop, repeating, nested, until the screen goes dark.

What makes the codebase worth studying is not any individual clever trick — it is the discipline of application. The same pattern, applied with the same care, to 461 maps, 260 species, 134 move animations, dozens of event scripts. The result is a ROM that could plausibly have shipped on real hardware in 1998, running on a chip that predates most of the readers of this book.

If you've read this far, you have the vocabulary to read any file in the repository and understand what it's doing. The best next step is to pick something that interests you — a Pokémon's base stats, a gym puzzle, a battle animation — open the source, and follow it down. Chapter 1 described how the cartridge works. The rest of the chapters described how the code uses it. Now the code is yours to read, change, and build.

*Start at [Chapter 1](01-the-cartridge.md) if you want to trace the architecture from first principles, or read `docs/overview.md` for a single-page orientation to every subsystem.*
