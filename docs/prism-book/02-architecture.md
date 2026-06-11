# Chapter 2 — Architecture & Idioms

*The whole game is data tables, pointer indirection, fixed-size records, and far-call trampolines. Internalize that and any file in the repo will make sense.*

---

## The Shape of the Codebase

Open the repo root and you will see five top-level directories that matter before anything else: `home/`, `engine/`, `battle/`, `event/`, and `data/`. They are not organised by feature — they are organised by *where the code lives in the cartridge address space*, which on a Game Boy Color is the fundamental structural constraint everything else bends around.

The GBC CPU sees a 16-bit address space. The bottom half (`$0000–$7FFF`) is ROM. The top half is RAM, I/O registers, and a small high-RAM slice. The ROM half is split into two regions: `$0000–$3FFF` is **ROM0**, the home bank — always mapped, always reachable with a plain `call`. Above that, `$4000–$7FFF` is a single **ROMX** window: one bank at a time, swapped in by writing to the MBC (memory bank controller). Pokémon Prism uses an MBC3 and has 117 ROMX banks on top of ROM0.

The implication is simple and non-negotiable: code in one ROMX bank *cannot* `call` directly into another ROMX bank. If bank 12 tries to `call` a function in bank 37, the CPU will happily jump to `$4000–$7FFF` — but the window will still contain bank 12. The called "function" will be garbage. Every cross-bank call requires the bank to be changed first, and changed back afterwards.

This is not a problem unique to Pokémon Prism. It is the fundamental shape of every Game Boy game. The solution Prism inherits from the original Pokémon Crystal codebase — and extends — is a layered trampoline system.

---

## `home/` vs Everything Else

`home/` is the ROM0 library. Everything in that directory is always mapped and can be called with an ordinary `call` from anywhere in the program. It is the universal dispatch layer. The directory contains about 60 files — not because ROM0 is large (it is only 16 KB) but because those files are the *entry points* for every major subsystem: the scripting VM, the map loader, the audio driver, the battle engine shim, the text printer, and the far-call machinery itself.

`engine/`, `battle/`, and `event/` live in ROMX. Their code is reachable only through trampolines. `data/` is also banked — ROM0 is too small to hold hundreds of kilobytes of base stats, movesets, map blocks, and sprite graphics.

A useful mental picture: ROM0 is the switchboard. You dial into it from anywhere, it routes the call to whichever ROMX bank holds the destination, and it patches you back through when the callee returns.

---

## Far-Call Machinery

### The problem, stated concretely

Suppose `engine/overworld.asm` (ROMX bank N) wants to call `engine/scripting.asm` (ROMX bank M). A plain `call ScriptDispatch` will jump to the right address, but bank N is still mapped. The CPU executes whatever bytes bank N has at that address instead of `ScriptDispatch`. Wrong bank, wrong code, probably a crash.

The fix is always the same: save the current bank, switch to the target bank, call the function, restore the saved bank. The machinery in `home/farcall.asm` and `rst.asm` encodes that sequence into a handful of reusable trampolines.

### `farcall` and `callab` — the `rst` path

The most common way to make a cross-bank call is the `farcall` macro (defined in `macros/rst.asm`):

```asm
; macros/rst.asm
MACRO callba ; bank, address
    rst FarCall
    dbw BANK(\1), \1
ENDM
```

`BANK(\1)` and the address of the target function are emitted as a three-byte inline record right after the `rst FarCall` instruction. The CPU executes `rst FarCall`, which is a one-byte call to address `$08` in ROM0 — the `FarCall` label in `rst.asm`:

```asm
; rst.asm
FarCall::
    jp StackFarCall
```

`StackFarCall` (in `home/farcall.asm`) is the trampoline itself:

```asm
; home/farcall.asm
StackFarCall::
; Call the following dba pointer on the stack
; Preserves a, bc, de, hl
    ldh [hFarCallSavedA], a
    ld a, l
    ldh [hPredefTemp], a
    ld a, h
    ldh [hPredefTemp + 1], a

    pop hl              ; pop return address — now hl points at the dbw record
    ld a, [hli]         ; read bank byte
    ldh [hBuffer], a
    ; ... (bit 7 check decides call vs jump)
    ldh a, [hROMBank]
    push af             ; save current bank on stack
    ld a, [hli]
    ld h, [hl]
    ld l, a             ; hl = target address
    ; fallthrough to FarCall_RetrieveBankAndCallFunction
```

The trampoline pops the return address (which now points at the inline `dbw` record), reads the bank, pushes the old bank, switches banks, then calls the function. When that function returns, execution falls into `ReturnFarCall`, which restores the saved bank before returning to the original caller. `hROMBank` (a hardware I/O shadow in HRAM) tracks which bank is currently mapped so the restore works correctly even under nested farcalls.

The `jpba` variant (`db BANK(\1) | $80, ...`) sets bit 7 of the bank byte; `StackFarCall` checks that bit to decide whether to `call` (and push a return address) or `jp` (tail-call, no return). This is how `predef_jump` and `jpba` implement efficient tail calls across banks.

### `callfar` is an alias

The macro `callfar` is not defined separately — the CLAUDE.md docs refer to `farcall`/`callab`/`callfar` as a family, but in practice the dominant macro is `callba` (emitting the three-byte inline record for `StackFarCall`) and the named `farcall` usage is the same mechanism. Search the codebase for `jpba` to find tail-call-across-bank patterns; search for `callba` or the `farcall` family for call-and-return patterns.

### `rst` vectors — one-byte utility calls

The `rst` instruction is a one-byte `call` to one of eight fixed addresses: `$00`, `$08`, `$10`, `$18`, `$20`, `$28`, `$30`, `$38`. Because each takes only one byte (versus three for a full `call`), they are reserved for the hottest utility functions. `rst.asm` at the repo root defines the full layout:

| Address | Label | Purpose |
|---------|-------|---------|
| `$00` | `NULL` / crash | Triggered on null-pointer call; halts with register dump |
| `$08` | `FarCall` | → `StackFarCall` — cross-bank trampoline |
| `$10` | `DrawBattleHPBar` | Draw HP bar (inline `jpba`) |
| `$18` | (text sentinel) | `GenericDummyText` — empty text block |
| `$20` | `GenericBankswitch` | → `_GenericBankswitch` — multi-mode bank switch |
| `$28` | `AddNTimes` | → `_AddNTimes` — multiply and add (walk fixed-size arrays) |
| `$30` | `Predef` | → `_Predef` — predefined-function dispatch |
| `$38` | `CopyBytes` | → `_CopyBytes` — bulk memory copy |

`AddNTimes` and `CopyBytes` appear hundreds of times throughout the codebase. Because fixed-size records are the dominant data structure, `rst AddNTimes` (walk N bytes × index) and `rst CopyBytes` (copy N bytes) are effectively primitive instructions.

---

## The `predef` System

Even `farcall`/`callba` bakes the bank number into the caller as an inline constant. If a function moves to a different bank during a refactor, every caller that used `callba` with a hardcoded bank needs updating — or the linker needs to patch it. RGBDS does compute `BANK(label)` automatically, so `callba MyFunc` always emits the correct bank. But there is a second problem: banked code calling *other* banked code. If bank N uses `callba` to call bank M, the call goes through ROM0 as expected, but bank N had to know the address and bank of its target at assembly time. When modules are large and cross-cutting, this creates tight coupling.

The `predef` system solves this with a level of indirection: a central table of function pointers, indexed by an 8-bit ID, lives at a known address (`PredefPointers` in `data/predefs.asm`). Any caller can reach any predef function using only the index number — no hardcoded bank.

`data/predefs.asm` is a sequential list of `add_predef` macros:

```asm
; data/predefs.asm (excerpt)
PredefPointers::
    add_predef LearnMove          ;00
    add_predef HealParty
    add_predef FlagAction
    add_predef EventFlagAction
    add_predef ComputeHPBarPixels
    ; ...
    add_predef StartBattle        ;10
    ; ...
    add_predef GetFrontpic        ;20
```

`add_predef` is defined in `macros/predef.asm`:

```asm
; macros/predef.asm
MACRO add_predef
\1Predef::
    dbw BANK(\1), \1
ENDM
```

Each entry emits three bytes: one bank byte plus a two-byte address, using the same `dbw` layout as `callba`'s inline record. The assembler computes `BANK(LearnMove)` automatically, so the table is always correct regardless of where functions end up after linking.

Calling a predef uses `rst Predef` via the `predef` macro:

```asm
; macros/predef.asm
MACRO predef
    rst Predef
    db (\1Predef - PredefPointers) / 3
ENDM

MACRO predef_jump
    rst Predef
    db ((\1Predef - PredefPointers) / 3) | $80
ENDM
```

The byte after `rst Predef` is the index into `PredefPointers` (dividing byte offset by 3 converts byte offset to entry index). `_Predef` in `home/predef.asm` does the lookup:

```asm
; home/predef.asm
_Predef::
; Call predefined function on the stack.
; Preserves bc, de, hl.
    ; ... (save hl into hPredefTemp)
    pop hl                  ; pop return address → points at index byte
    ld a, [hli]
    ldh [hBuffer], a        ; read the index byte
    ; bit 7 = jump vs call
    ldh a, [hROMBank]
    push af                 ; save current bank
    ld a, BANK(PredefPointers)
    call Bankswitch         ; switch to the predef table's bank
    ; ... (index into table, read bank+address)
    call Bankswitch         ; switch to target function's bank
    call RetrieveHLAndCallFunction
    jr ReturnFarCall        ; restore bank, return
```

`_Predef` switches to the bank holding `PredefPointers`, reads the three-byte entry, then switches again to the function's own bank before calling it. The caller never needed to know either bank number — just the symbolic name, which the assembler resolves to an index at build time.

The rule of thumb: use `callba` / `jpba` when calling from ROM0 into a ROMX function. Use `predef` when calling from ROMX into another ROMX function, especially across module boundaries.

---

## The Enum and Constant System

Every game ID — species, move, item, map, event flag, music track — is a named constant defined exactly once in `constants/`. This is the single source of truth that makes the data tables coherent.

### `const` — sequential integers

```asm
; macros/enum.asm
MACRO const_def
const_value = 0
ENDM

MACRO const
if strcmp("\1", "skip")
\1 EQU const_value
endc
const_value = const_value + 1
ENDM
```

`const_def` resets a running counter to zero. Each `const NAME` binds `NAME` to the current counter value and increments. So the species list in `constants/pokemon_constants.asm` works like this (after `constants.asm` does `const_def` and `const NO_POKEMON`):

```asm
; constants/pokemon_constants.asm (excerpt)
    const BULBASAUR    ; = 1  (NO_POKEMON was 0)
    const IVYSAUR      ; = 2
    const VENUSAUR     ; = 3
    ; ...
```

`shift_const NAME` assigns `NAME EQU (1 << const_value)` instead of the raw value — used for bitmask constants like hardware flags.

### `enum` — arbitrary-start sequences

```asm
MACRO enum_start      ; optional argument sets start value and direction
__enum__ = \1         ; default 0; second arg sets step (+1 or -1)
ENDM

MACRO enum
\1 = __enum__
__enum__ = __enum__ + __enumdir__
ENDM
```

`enum` is used where the start value matters (item IDs that must not start at zero for legacy reasons, for instance) or where you need to count down. `enum_set VALUE` jumps the counter mid-sequence.

### `constants.asm` — the aggregator

Every `.asm` file begins with `INCLUDE "includes.asm"`, which pulls in:

```asm
; constants.asm (excerpt)
INCLUDE "macros.asm"          ; first — so macros are defined before use
INCLUDE "gbhw.asm"

    const_def
    const NO_POKEMON
INCLUDE "constants/pokemon_constants.asm"

    const_def
    const NORMAL
INCLUDE "constants/type_constants.asm"

    const_def
    const NO_MOVE
INCLUDE "constants/move_constants.asm"
; ... ~30 more INCLUDE lines
```

Notice the pattern: before each large block, `constants.asm` does `const_def` (resetting the counter to zero) and optionally emits a sentinel `const` (`NO_POKEMON = 0`, `NO_MOVE = 0`) before including the family's file. This ensures every family's IDs start at a predictable base, while keeping each family's source file free of the sentinel — you never accidentally get a species with numeric value 0.

The result: every assembled file sees the full universe of constants from `SPECIES_BULBASAUR` through `SFX_LAST_SOUND`, with no header guards needed, because RGBDS processes each file in one pass and `EQU` is not duplicable.

---

## The Macro Layer

`macros.asm` aggregates 19 files from `macros/` and then defines a further collection of utility macros inline. The macro library covers two broad categories.

### Data-structure builder macros

These emit bytes in a specific layout, turning a human-readable declaration into a correctly-packed binary record. Examples:

- `add_predef` (`macros/predef.asm`) — emits a 3-byte function pointer entry  
- `dba LABEL` (`macros.asm`) — emits `BANK(LABEL), LOW(LABEL), HIGH(LABEL)` — a 3-byte far pointer used everywhere in map headers and pointer tables  
- `dbw B, W` — emits one byte then a two-byte word (little-endian); `dwb W, B` is the reverse  
- `dn A, B` — packs two 4-bit nibbles into one byte; used in egg group and DV fields  
- `RGB R, G, B` — emits a 2-byte GBC palette entry (5-bit components packed as `BBBBBGGGGGRRRRR`)  
- `warp_def`, `person_event`, `coord_event`, `signpost` (`macros/map.asm`) — emit map event records; see [Chapter 5](05-anatomy-of-a-map.md)  
- `text`, `line`, `cont`, `para`, `done` (`macros/text.asm`) — emit text VM bytecode  
- `step_right N`, `turn_head DIR`, `end_movement` (`macros/movement.asm`) — emit NPC movement script bytecode  

### Control and arithmetic macros

- `coord HL, X, Y` — computes `hl = wTileMap + SCREEN_WIDTH * Y + X`, a tilemap address  
- `lb R, HI, LO` — loads a 16-bit immediate from two 8-bit halves into register pair R  
- `jumptable` — emits the `rst JumpTable` call plus optional first-entry pointer; the jump table pattern is used for state machines throughout the engine  
- `farcall` / `callba` / `jpba` — the far-call family described above  
- `predef` / `predef_jump` — predef dispatch  
- `debug_mode_flag` — emits either `scf` (set carry) or `and a` (clear carry) depending on whether `DEBUG_MODE` is defined at build time, always occupying exactly one byte so the addresses of surrounding code are stable across builds  

The convention worth internalising: **macros that emit data are named like nouns** (`warp_def`, `dba`, `RGB`); **macros that emit code are named like verbs or calls** (`farcall`, `predef`, `coord`). The boundary is not always crisp, but the pattern holds enough to be a useful reading guide.

---

## Coding Conventions in Practice

The project's code-conventions document (read `docs/code-conventions.md`) is brief by design. The conventions are:

- **Comments that document a label, macro, or function must appear on the line immediately before the definition**, not inline on the same line. This is consistently followed across `home/` and `engine/`.

Beyond that single explicit rule, a few implicit conventions appear throughout the codebase:

**Fixed-size records everywhere.** Data tables are arrays of uniformly-sized entries. The move table is a fixed number of bytes per move. The base-stats table is a fixed number of bytes per species. The predef table is three bytes per entry. This regularity is what makes `rst AddNTimes` so useful: indexing into any table is multiply-and-add.

**Pointer tables for variable-length data.** When records genuinely vary in size (Pokémon learnsets, map event lists, trainer parties), a separate pointer table maps an ID to an address. The data itself can be any length. The pointer is always the same size. This pattern appears in `data/evos_attacks_pointers.asm`, `data/base_stats.asm`, and the map header two-level lookup.

**HRAM for hot variables.** Frequently-read variables like `hROMBank`, `hBuffer`, `hPredefTemp`, and `hFarCallSavedA` live in the high RAM region `$FF80–$FFFE`. HRAM is accessible with the single-byte `ldh` instruction rather than the two-byte `ld [addr], a`, saving a cycle and a byte on every access. The trampoline code in `home/farcall.asm` uses HRAM exclusively — it needs the save/restore path to be as fast as possible.

**Conditional compilation via `DEF()`**. Debug-only code is wrapped in `IF DEF(DEBUG_MODE) ... ENDC`. The `debug_mode_flag` macro ensures that conditional branches occupy a fixed byte count regardless of build type, preventing address shifts between the debug ROM and the release ROM.

**No global mutable state passed through registers across banks.** Register values are not reliably preserved across a `farcall` unless the trampoline explicitly saves them (most do preserve `bc`, `de`, `hl`, but caller-saved patterns vary). Shared mutable state lives in WRAM. Transient arguments to banked functions are passed in registers documented in the function's header comment.

---

## The Mental Model

If you step back from the details, the whole architecture reduces to four principles that repeat at every scale:

1. **Data tables.** Almost every game entity — Pokémon species, moves, items, maps, NPCs — exists as a row in a table. The table index is the canonical identity of the thing. Code manipulates IDs, not inline data.

2. **Pointer indirection.** When data is variable-length or when it must be reached across banks, a fixed-size pointer table maps IDs to addresses. The lookup is always two steps: index into the pointer table, dereference the pointer.

3. **Fixed-size records.** Where possible, records are the same size. This makes indexing arithmetic rather than traversal: entry N is at `base + N * record_size`.

4. **Far-call trampolines.** ROM0 is the universal dispatcher. Banked code reaches banked code by going up through ROM0, switching banks, calling, and coming back through the same path on the return. The `farcall`/`callba` family handles call-and-return; `predef`/`predef_jump` handle it without hardcoding the target bank in the caller.

These four principles interact constantly. The predef table is a fixed-size pointer table. The map header lookup is a two-level pointer indirection with fixed-size records. The scripting VM is a far-call into banked code, dispatched through a jump table indexed by a command byte. Once you see the pattern, it is everywhere — and that is precisely what makes the codebase readable.

---

*Chapter 3 maps the full address space — ROM0, ROMX, WRAM, SRAM, HRAM — and explains how each region is used at runtime. Continue to [Chapter 3](03-the-memory-map.md).*
