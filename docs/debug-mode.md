# Debug Mode

Pokeprism ships with a substantial set of debugging features that are compiled
into a separate ROM via the `DEBUG_MODE` build flag. This doc covers:

1. How to build the debug ROM
2. The `DEBUG_MODE` macro pattern (how code is gated)
3. The in-game debug menus (Main-menu and Start-menu variants) and what each option does
4. The `/patch/` bspcomp framework (post-build patcher)

If you want to launch the game in a custom state (team, map, flags) *without*
rebuilding, see [pokeprism-devtools](https://github.com/ricccec/pokeprism-devtools) — the `prism-dev` tool covers
that. The debug menu is the right call for one-off interactive tweaks; the
`prism-dev` tool is for repeatable, version-controlled initial states.

---

## Building the debug ROM

The `Makefile` produces two ROMs from the same source:

| Target           | ROM file                  | DEBUG_MODE | Notes                                         |
|------------------|---------------------------|------------|-----------------------------------------------|
| `make prism`     | `pokeprism.gbc`           | yes        | Debug build. Same alias as `make pokeprism.gbc`. |
| `make nodebug`   | `pokeprism_nodebug.gbc`   | no         | Release build.                                |
| `make all`       | both (+ `gbs`, freespace) | both       | Default in most workflows.                    |

The flag is wired up at `Makefile:104`:

```make
$(pokeprism_obj):         RGBASMFLAGS += -DDEBUG_MODE
$(pokeprism_nodebug_obj): RGBASMFLAGS +=
```

Every code path gated on `DEBUG_MODE` is therefore present in `pokeprism.gbc`
and absent from `pokeprism_nodebug.gbc`. Both ROMs share the same SRAM layout
and save format, so a `.sav` file is interchangeable between them.

---

## The `debug_mode_flag` macro

The codebase uses a one-byte macro to branch on debug mode without shifting
addresses between the two builds (`macros.asm:327-335`):

```asm
MACRO debug_mode_flag
    ; This macro sets the carry flag depending on whether debug mode is on or off.
    ; It takes up one byte either way, preventing address shifts between modes.
    if DEF(DEBUG_MODE)
        scf       ; set carry → "debug is on"
    else
        and a     ; clear carry → "debug is off"
    endc
ENDM
```

Callers test the carry flag right after invoking it. Example from
`engine/main_menu.asm:23`:

```asm
debug_mode_flag
jr nc, .ok      ; skip debug-only path in release builds
```

Larger debug-only blocks (entire functions, menu entries, map warps) are gated
with `IF DEF(DEBUG_MODE) ... ENDC` instead. Files that gate code this way:

- `macros.asm` — the macro itself
- `engine/main_menu.asm` — the "Debug options" entry on the main menu
- `engine/startmenu.asm` — the "Debug" entry on the in-overworld start menu
- `maps/BattleTowerEntrance.asm` — debug-only warps

`grep -rln DEBUG_MODE` will find all of them.

---

## In-game debug menus

There are **two** distinct debug menus in pokeprism. They serve different
purposes.

### 1. Main-menu "Debug options" (`MainDebugOptions`)

Shown as the **fourth** option on the title-screen main menu when the debug
ROM is running (`engine/main_menu.asm:58, 68`). It's a small recovery menu
for the save file itself — does not require an existing save.

Source: `engine/main_menu_debug.asm`. Three actions:

| Option            | What it does                                                                                     |
|-------------------|--------------------------------------------------------------------------------------------------|
| Reset clock       | Sets bit 7 of `sRTCStatusFlags` so the game asks for date/time again on next boot.               |
| Erase saved data  | Zero-fills all four SRAM banks (`SRAM_Begin..SRAM_End`).                                          |
| Fix build number  | Overwrites `sBuildNumber` with the current build's number, bypassing the save-incompatibility check. |
| Back              | Return to main menu.                                                                             |

Each destructive option requires a confirmation press before applying, then
reboots the game.

### 2. Overworld "Debug" sub-menu (`DebugMenu`)

The big one. Shown as a menu entry in the in-game Start menu when the debug
ROM is running (`engine/startmenu.asm:138-142`, opened by `StartMenu_Debug` at
line 379). The menu is interactive and operates on the live WRAM state, so
changes take effect immediately.

Source: `engine/debug_menu.asm` (engine), `engine/debug_menu_contents.asm`
(menu definitions), `macros/debug_menu.asm` (DSL macros).

Top-level options (`DebugMainMenu` at `engine/debug_menu_contents.asm:1`):

| Option         | Submenu                  | Capability                                                                              |
|----------------|--------------------------|------------------------------------------------------------------------------------------|
| Get #mon       | `DebugGetPokemonMainMenu`| Spawn any species at any level (1–100) with an optional held item. Also Get-egg variant. |
| Manage Items   | `DebugManageItemsMenu`   | Add arbitrary items to the bag; manage TMs/HMs.                                          |
| Manage Money   | `DebugMoneyMenu`         | Edit trainer ID, money, coins.                                                           |
| Warp Anywhere  | `DebugWarpMenu`          | Pick any map by ID and warp to it.                                                       |
| Edit flags     | `DebugFlagsMenu`         | Toggle engine flags (e.g. fly-points) and event flags (story progression).               |
| Memory Access  | `DebugMemoryAccessMenu`  | Read/write arbitrary WRAM addresses; jump to (execute) arbitrary ROM addresses.          |
| Miscellaneous  | `DebugMiscellaneousMenu` | Mult/div test, sound test, stopwatch test, exp-group test, trigger the credits roll.     |
| Pics           | `DebugPicTestMenu`       | Sprite preview: cycle through every trainer class or Pokémon species.                    |
| Cancel         | —                        | Close the menu, return to overworld.                                                     |

The main-menu loop also displays the live game timer in the top bar
(`engine/debug_menu.asm:39-110`).

### Menu DSL

The menu DSL (`macros/debug_menu.asm`) makes adding new entries cheap. The
shape is:

```asm
ExampleMenu: debug_menu " Title", ParentMenu, .options, DefaultAction, LoadAction
.options debug_menu_options .a, .b, .c
.a debug_option "Label A", ActionLabelA
.b debug_option "Label B", ActionLabelB, CursorHandlerB, SelectHandlerB
.c debug_option "Back", DebugMenuCancel
```

- `debug_menu` declares a menu with parent (`0` exits), an options list, an
  optional default action, and an optional one-shot load action.
- `debug_menu_options` accepts up to 13 entries.
- `debug_option` accepts (name, action, cursor-handler, select-handler) —
  cursor handler runs on L/R, select handler on SELECT.
- `debug_exit` / `debug_exit_jp` call `DebugMenuExit` with an exit mode and
  optional script address — used to close the menu and resume gameplay,
  possibly running a script first.

---

## The `/patch/` bspcomp framework

`/patch/` is a separate, post-build patching system. It's invoked manually
via `make patch` (`Makefile:64, 157-158`), which compiles `patch/patch.txt`
into `pokeprism.bsp` using `utils/bspcomp`.

What is a `.bsp`? It's a binary patch file in the bspcomp format. Applied to
a vanilla Pokémon Crystal 1.1 ROM (sha1 `f2f52230b536214ef7c9924f483392993e226cfb`)
it produces the pokeprism ROM. The `make patch` target requires
`baserom.gbc` (the Crystal ROM) to be present — the build asserts on its
SHA1 (`Makefile:160-162`).

The `.txt` files in `/patch/` are bspcomp source. Read `docs/macros-and-constants.md`
for general macro context; the patch DSL is documented inline in the files.

**Important second use**: many `.txt` files run *inside* the bspcomp patch as
**save-file migrations**. When a player loads a save built on an older version,
`patch/save_patches.txt` and friends run a sequence of in-place fix-ups on
the SRAM image (e.g. resetting RTC state, repairing a broken TM, applying a
party-data correction). This is why builds can change save layout without
breaking existing saves.

Key files (read these to extend the patcher):

| File                          | Purpose                                                                            |
|-------------------------------|-------------------------------------------------------------------------------------|
| `patch.txt`                   | Entry point. Defines variables and includes every other file.                       |
| `constants.txt`               | Shared constants (variable IDs, magic numbers).                                     |
| `main.txt`                    | Top-level patch logic.                                                              |
| `detection.txt`               | Detect ROM version / save state.                                                    |
| `version_selections.txt`      | Branch on which version the user is upgrading from.                                 |
| `patching.txt`                | Generic patching workflow (lock pos, apply, checksum).                              |
| `savefile.txt`                | Save file structure helpers.                                                        |
| `save_patches.txt`            | Save-file migration routines (RTC fix, Iron Head TM fix, Caterpie quest fix, etc.). |
| `save_patch_list.txt`         | Ordered list of save patches to apply.                                              |
| `save_patch_utils.txt`        | seek/read/write/flag helpers used by save patches.                                  |
| `apply_party_patches.txt`     | Party-data corrections.                                                             |
| `pokemon_functions.txt`       | Pokémon mutation utilities (evolve, level-up, recompute stats).                     |
| `item_functions.txt`          | Item manipulation utilities.                                                        |
| `experience.txt`              | EXP / level-up arithmetic.                                                          |
| `util.txt`, `random.txt`      | RNG and string utilities.                                                           |
| `sha1sum.txt`                 | SHA1 hashing in bspcomp.                                                            |
| `pokecenter_check.txt`        | Pokémon Center heal logic for the patched build.                                    |
| `gold_token_patch.txt`        | Specific event/item fix.                                                            |
| `gbs.txt`                     | Patches for the GBS (music-only) build.                                             |
| `crystal.ips` (binary)        | IPS diff against vanilla Crystal — reference baseline.                              |
| `_*.ips`, `_*.bin`, `_*.txt`  | Generated at build (release/debug IPS diffs, hashes, version string).               |
| `lol.txt` / `lol.ips`         | Easter-egg patch.                                                                   |

Generated files (the `_*` set) are produced by the `make patch` and `make all`
targets — they're not source. See `Makefile:164-185` for the recipes.

---

## Quick reference

- Enable the debug menus: `make prism` (or `make all`), then run `pokeprism.gbc`.
- Open the overworld debug menu: in-game Start menu → **Debug**.
- Open the title-screen debug recovery menu: title screen → **Debug options**.
- Find every `DEBUG_MODE`-gated piece of code: `grep -rln DEBUG_MODE *.asm`.
- Find every debug-menu submenu: `grep -n "debug_menu " engine/debug_menu_contents.asm`.
- Rebuild the bspcomp patch: `make patch` (needs `baserom.gbc`).
