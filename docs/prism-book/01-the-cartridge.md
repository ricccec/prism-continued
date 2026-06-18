# Chapter 1 — The Cartridge

*Two megabytes of banked ROM, a handful of assembly files, and one very strict toolchain version — this is what Pokémon Prism is made of.*

---

## What Is Pokémon Prism?

Pokémon Prism is a complete Game Boy Color ROM hack of Pokémon Crystal. It ships as a 2 MB `.gbc` file — a new region, 260+ Pokémon, 461 maps, new moves, minigames, and a story that diverges from Crystal's almost immediately. But the headline fact for anyone reading this book is the implementation: the codebase is essentially 100% RGBASM dialect assembly, with Python and C helpers for pre-processing graphics and audio. There is no C game code, no scripting framework borrowed from a modern engine, no abstract layer. It's assembly all the way down, every frame, every menu, every battle calculation.

That makes it an unusually pure object of study. Every trick the engine plays is visible in the source. When something looks like magic, there's a fifteen-line routine somewhere that explains it.

---

## The Target Hardware

The Game Boy Color's CPU is a custom Sharp SM83 running at roughly 4 MHz double-speed mode (8 MHz effective). It has a 16-bit address bus, which means the CPU can directly address at most 64 KB of memory at a time. The full memory map looks roughly like:

| Address range | What lives there |
|---------------|-----------------|
| `$0000–$3FFF` | ROM bank 0 — always mapped |
| `$4000–$7FFF` | Switchable ROM bank — currently active ROMX |
| `$8000–$9FFF` | VRAM (banked: bank 0 and bank 1 on GBC) |
| `$A000–$BFFF` | External RAM / RTC registers (MBC3) |
| `$C000–$DFFF` | Work RAM (WRAM, banked on GBC: 8 × 4KB banks) |
| `$FE00–$FE9F` | OAM — sprite attribute table |
| `$FF00–$FFFF` | Hardware registers and HRAM |

The 64 KB address space is the fundamental constraint that shapes everything about this codebase. The game's ROM is 2 MB — thirty-two times the size of the directly addressable window. The hardware solves this with a *memory bank controller* (MBC3 in this cartridge's case), a chip that sits between the CPU and the ROM and remaps the `$4000–$7FFF` window on demand. You write a bank number to a special address, and the MBC3 swaps a different 16 KB slice into view. The rest of the ROM still exists; it's just invisible until you ask for it.

---

## ROM Banking: The Shape of 2 MB

The cartridge's 2 MB divides into **128 × 16KB banks**:

- **Bank 0 (ROM0)** occupies `$0000–$3FFF`. It is *always* mapped — the CPU can reach it from any context without any setup. This is the home bank. The code that lives here is the runtime library: interrupt handlers, restart vectors, bankswitch primitives, `farcall` trampolines, the audio driver tick, the joypad reader. Anything that might be called from arbitrary banked code must live here.

- **Banks 1–127 (ROMX)** are switchable. Only one is visible at a time, at `$4000–$7FFF`. The game code running in a banked section can call functions in other banked sections only through the trampoline mechanisms in ROM0 — it cannot jump directly to an address in a different bank.

The MBC3 register that controls which bank is mapped lives at `$2000–$3FFF` in the cartridge address space. Writing to it takes effect immediately on the next read from `$4000`. The home bank's `Bankswitch` routine handles the actual write:

```asm
; home/farcall.asm — the inner loop of a cross-bank call
FarCall_RetrieveBankAndCallFunction:
    ldh a, [hBuffer]
    and $7f
    ldh [hROMBank], a       ; remember current bank in HRAM
    ld [MBC3RomBank], a     ; flip the MBC3 register
    call RetrieveHLAndCallFunction
; ... (restore bank on return)
```

Restoring the previous bank on return is equally important — the pushed `af` on the stack holds the caller's bank number, and `ReturnFarCall` pops it back into `MBC3RomBank` before the `ret` fires.

### Calling Across Banks in Practice

Because you can't `call` a label in a different bank directly, the codebase uses a family of macros built on the RST vector at `$08` (`FarCall`):

```asm
; macros/rst.asm
MACRO callba ; call a label by bank+address
    rst FarCall
    dbw BANK(\1), \1   ; one byte bank, two byte address, inlined after rst
    ENDM

MACRO jpba   ; jump (tail-call) to a label in another bank
    rst FarCall
    dbw BANK(\1) | $80, \1
    ENDM
```

`BANK(\1)` is an RGBASM built-in that resolves to the bank number the linker assigned to symbol `\1`. At assembly time that number is not yet known; the assembler emits a fixup and the linker fills it in. The result is that you write `callba SomeFunction` and the toolchain handles the routing. The `$80` bit in `jpba` signals to the RST handler that this is a tail-call: don't push a return address.

There is also a lower-level dispatcher for more exotic switching needs — `_GenericBankswitch` in `home/bankswitch.asm` — which handles SRAM, WRAM, and VRAM banks in addition to ROM, decoding the type of switch from a byte embedded in the instruction stream.

---

## The RGBDS Toolchain

The project is built with **RGBDS 0.7.0** — exactly that version, no substitutes. RGBDS is the de-facto standard toolchain for Game Boy assembly, comprising:

| Tool | Role |
|------|------|
| `rgbasm` | Assembles `.asm` source files into relocatable `.o` objects |
| `rgblink` | Links `.o` files according to a linker script, producing the raw ROM binary |
| `rgbfix` | Patches the ROM header (title, checksums, MBC type, ROM size, CGB flag) |
| `rgbgfx` | Converts PNG images into Game Boy tile format (`.2bpp` / `.1bpp`) |

The version lock exists for a concrete reason. Prism uses ~427 symbol assignments in the old pre-`DEF` syntax (`sym EQU value`, `sym = value`). RGBDS 0.8 deprecated these; 1.0 removed them entirely. Using 0.8 or later produces hundreds of errors. Using 0.7.0 builds cleanly.

The command you'll run most:

```bash
make nodebug RGBDS="/tmp/rgbds-0.7.0/"
```

That produces three files: `pokeprism_nodebug.gbc` (the playable ROM), `pokeprism_nodebug.sym` (a symbol table for emulator debuggers), and `pokeprism_nodebug.map` (the full linker map). Chapter 11 covers the build system in depth; here it's enough to know the invocation.

---

## The High-Level ROM Layout

Prism's 118 used ROMX banks (plus ROM0) divide by purpose, as laid out in `contents/romx.link`:

| Bank range | Contents |
|------------|----------|
| ROM0 (`$00`) | Home bank — interrupt handlers, RST vectors, bankswitch, farcall, audio tick |
| `$01–$1F` | Code sections 1–18 plus specialised modules (battle core, evolution, effect commands) |
| `$20–$35` | More code sections + map block data, sprite sheets, Pokémon pics, tilesets |
| `$36–$4F` | Graphics — more pics, battle animation GFX, tilesets, overworld sprites |
| `$50–$70` | DED-compressed Pokémon cry audio (27 sections) |
| `$71–$76` | Code section 31, map scripts, tilesets, songs, enemy trainer data |

The picture is more granular than that summary suggests — individual banks hold a mix of sections (a code section and a couple of map-script sections can share a bank if they fit), and the linker script places them all explicitly. For instance, bank `$0E` holds:

```
ROMX $0E
    "Code 9"
    "Map Scripts 1"
    "DED small 7"
```

That's engine code, event scripts, and compressed audio sharing a 16 KB bank. The linker will error if you overfill it, which is why `docs/map-rom-budget.md` exists.

The code sections — named "Code 1" through "Code 31" — hold the bulk of the game engine: overworld, battle, menus, Pokémon mechanics. Map data (the `.blk` block grids) lives in its own sections so the linker can pack them tightly. Pokémon sprite pics are their own heavy sections (`Pics 1` through `Pics 21`). Audio and cry data fill the upper half of the address space.

---

## The Master Include Structure

The build assembles six translation units from six top-level `.asm` files, then links them all together. The most important is `main.asm`.

**`main.asm`** begins with two lines, then defines all 31 code sections:

```asm
; main.asm (top)
INCLUDE "includes.asm"

INCLUDE "home.asm"
INCLUDE "battle/files.asm"

INCLUDE "engine/intro_menu.asm"
INCLUDE "tilesets/collision.asm"

SECTION "Code 1", ROMX

INCLUDE "gfx/initialize_map.asm"
INCLUDE "engine/learn.asm"
; ...
```

Everything before the first `SECTION` directive ends up attached to whatever section is currently open — which at that point is the last section from `home.asm`. The `SECTION "Code 1", ROMX` line opens a new banked section; RGBASM will emit all subsequent bytes into it until the next `SECTION` statement. The linker then places each named section into the bank slot named in the linker script.

**`includes.asm`** is a two-line file:

```asm
; includes.asm
INCLUDE "version.asm"
INCLUDE "constants.asm"
```

`constants.asm` in turn includes all 38 constant definition files under `constants/` — species IDs, move IDs, item IDs, map group numbers, engine flag numbers, and so on. `macros.asm` (included via `constants.asm`) brings in all 21 macro definition files. Because `includes.asm` is included at the top of `main.asm`, every constant and macro is in scope for the rest of the build.

**`home.asm`** defines the ROM0 sections:

```asm
; home.asm (top)
INCLUDE "rst.asm"
INCLUDE "interrupts.asm"

SECTION "High Home", ROM0
INCLUDE "home/highhome.asm"
INCLUDE "home/crash.asm"
; ...
SECTION "Home", ROM0

INCLUDE "home/init.asm"
INCLUDE "home/predef.asm"   ; keep close to farcall (within reach of jr)
INCLUDE "home/farcall.asm"
INCLUDE "home/bankswitch.asm"
; ...
```

The comment on `predef.asm` — "keep close to farcall (within reach of jr)" — is a physical layout constraint. A `jr` instruction on the SM83 has a range of ±127 bytes. If `predef.asm` drifts too far from `farcall.asm` in the output binary, a branch silently stops reaching its target. Assembly programming at this level means thinking about not just what the code does but where it lives in memory.

The other five translation units (`audio.asm`, `gfx.asm`, `maps.asm`, `text.asm`, `wram.asm`) follow the same include-heavy pattern, each pulling in dozens of subsystem files and placing them in sections the linker script knows about.

---

## The Linker Scripts

Three `.link` files under `contents/` describe the final ROM layout:

- **`contents/homebank.link`** — places the ROM0 sections (`RSTs`, `Interrupts`, `High Home`, `Version`, `Header`, `Home`) at specific addresses, including `org $0100` for the cartridge header and `org $0150` for the start of home code.
- **`contents/romx.link`** — lists every ROMX bank from `$01` to `$76`, naming which sections go in each one.
- **`contents/wram.link`** and **`contents/sram.link`** — lay out work RAM and save RAM variables (covered in [Chapter 3](03-memory-map.md)).

`contents/contents.link` just includes all four:

```
; contents/contents.link
INCLUDE "contents/homebank.link"
INCLUDE "contents/romx.link"
INCLUDE "contents/wram.link"
INCLUDE "contents/sram.link"

VRAM 0
    "VRAM0"
VRAM 1
    "VRAM1"

HRAM
    "HRAM"
```

The linker enforces that every section named in `main.asm` (and the other translation units) has a corresponding entry in the linker scripts. If you add a new section and forget to place it, `rgblink` will error. If you overfill a bank, it will error. The scripts are the authoritative map of what goes where.

---

## A Sense of Scale

To make all of this concrete: a `make nodebug` run assembles roughly 90,000 lines of RGBASM source across several hundred files, links six object files against the linker scripts, and produces an exactly 2,097,152-byte ROM (`$200000` bytes — 128 × 16 KB). `rgbfix` then stamps in the header. The whole build takes a few seconds on a modern machine.

The output is a file that a 1998 Game Boy Color cartridge could theoretically have shipped on. The same hardware constraints apply. The same 4 MHz CPU. The same 64 KB address window. The fact that it works — that 461 maps, 260+ Pokémon, music, battle animations, and a scripting VM all fit and run — is a consequence of disciplined banking, compact data encoding, and thirty-odd years of community knowledge about squeezing the most out of this little machine.

---

*Where to next:* [Chapter 2](02-architecture.md) digs into the idioms and patterns that hold all this assembly together — how the engine structures its routines, how data tables work, and the conventions you'll see repeated everywhere in the codebase.
