# Chapter 9 — Text, Menus, Audio & Graphics

*The cartridge is a machine for generating pixels and sound; everything else is scaffolding to get you there.*

---

## 9.1 The Text Subsystem

Everything a player reads in Prism passes through a layered pipeline: source text is **Huffman-compressed at assemble time**, stored as compact byte sequences in ROM, and expanded character by character at runtime by a small interpreter. This section traces the pipeline from source to screen.

### 9.1.1 The Charmap — Text to Bytes

RGBDS converts string literals to bytes using a *charmap*: a table that maps character sequences to byte values. Prism's charmap lives in `macros/charmap.asm` and is built with a custom `ctxtmap` macro:

```asm
; macros/charmap.asm
MACRO ctxtmap
x = \2
___huffman_data_{02X:x} EQU %\3
___huffman_length_{02X:x} EQU strlen("\3")
    charmap \1, \2
ENDM
```

Each `ctxtmap` call does two things at once: it registers the string→byte mapping with RGBDS's `charmap` directive, and it records the **Huffman bit-pattern** (`\3`) and its length for use during compression. The control-code range starts at `LEAST_CONTROL_CHAR EQU $44`:

```asm
ctxtmap "<EMON>",   $44, 10100100
ctxtmap "<STRBF1>", $45, 00000111001000
ctxtmap "<PARA>",   $51, 0000000
ctxtmap "<PLAYER>", $52, 10100111100011
ctxtmap "<DONE>",   $57, 101001101
```

Byte values below `LEAST_PLACEABLE_CHAR` (`$60`) are control codes; values at or above `LEAST_TEXT_CHAR` (`$7f`) are printable characters. The `BOLDP` and `NOPKRS` tile references (`$3e`/`$3f`) live in the sub-`$44` range and are handled separately by the stats renderer — not by the text engine.

### 9.1.2 Text Macros — Authoring Dialogue

The dialogue authoring macros live in `macros/text.asm`. The key ones:

| Macro | What it emits | Effect at runtime |
|-------|--------------|-------------------|
| `ctxt "..."` | `TX_COMPRESSED` byte + Huffman-coded text | Begin a compressed text run |
| `text "..."` | Raw byte string (uncompressed) | Begin an uncompressed run |
| `line "..."` | `<LINE>` code + compressed text | Move cursor to bottom row |
| `cont "..."` | `<CONT>` code + text | Scroll and continue |
| `para "..."` | `<PARA>` code + text | Clear box, new paragraph |
| `done` | `<DONE>` code | End text block |
| `prompt` | `<PROMPT>` code | Show yes/no prompt |

The compression happens entirely at assemble time. When `ctxt` is used, `___compressing_text` is set to `1` and every character is fed through `___dchr`, which accumulates Huffman bits and flushes complete bytes:

```asm
; macros/text.asm — ___dchr (simplified)
DEF ___ct_bits = (___ct_bits << ___huffman_length_{02X:___chr}) | ___huffman_data_{02X:___chr}
DEF ___ct_length = ___ct_length + ___huffman_length_{02X:___chr}
; flush complete bytes ...
if ___chr == "<DONE>" || ___chr == "<SDONE>" || ___chr == "<PROMPT>"
    DEF ___compressing_text = 0
    assert ___ct_out_bytes <= ___ct_in_bytes, "ctxt should be text"
endc
```

The final `assert` is a build-time safety net: if compressed output is ever *larger* than uncompressed input, the assembler fails and you know to switch to `text` instead. The scheme exploits the skewed character frequency of English Pokémon dialogue — short codes for `<PARA>` and `<DONE>`, longer ones for rare control characters.

`text_far` and `text_jump` encode a three-byte far pointer (high byte, low byte, bank) for following text chains across ROM banks:

```asm
; macros/text.asm
MACRO text_far
    db HIGH(\1) - ($40 - (LEAST_CONTROL_CHAR - $40))
    db LOW(\1)
    db BANK(\1)
ENDM
MACRO text_jump   ; like text_far but sets bit 7 of bank = don't return
    db HIGH(\1) - ($40 - (LEAST_CONTROL_CHAR - $40))
    db LOW(\1)
    db BANK(\1) | $80
ENDM
```

The high-byte encoding shifts the pointer value into the range that the text interpreter recognises as a "follow this pointer" command rather than a printable character.

### 9.1.3 The Text Engine — Runtime Interpreter

The text box itself is drawn in `home/text.asm`. `SpeechTextBox` / `TextBox` calculates the correct tilemap coordinate from `TEXTBOX_X`, `TEXTBOX_Y`, `TEXTBOX_WIDTH`, and `TEXTBOX_HEIGHT` (all defined at the top of the file), places the box-drawing characters (`┌`, `─`, `┐`, `│`, `└`, `┘`), and sets the text palette to slot 7.

Printing runs through `TextControlCodeJumptable` (line 300 of `home/text.asm`), a word table with one entry per control-code byte from `$44` onward:

```asm
TextControlCodeJumptable::
    dw PlaceEnemyMonNick        ; "<EMON>"
    dw PlaceStringBuffer1       ; "<STRBF1>"
    ; ...
    dw Paragraph                ; "<PARA>"
    dw PrintPlayerName          ; "<PLAYER>"
    dw PrintRivalName           ; "<RIVAL>"
    dw ContText                 ; "<CONT>"
    dw DoneText                 ; "<DONE>"
    dw PromptText               ; "<PROMPT>"
    dw LinebreakText            ; "<LNBRK>"
```

When the engine encounters a byte in the control range it computes `hl = TextControlCodeJumptable + (byte - LEAST_CONTROL_CHAR) × 2`, loads the handler address, and jumps. All name-placement handlers use the same `print_name` macro:

```asm
MACRO print_name
    push de
    ld de, \1
    jp PlaceCommandCharacter
ENDM

PrintPlayerName: print_name wPlayerName
PlaceStringBuffer1: print_name wStringBuffer1
```

`PlaceCommandCharacter` then calls `PlaceString`, which writes tiles into the tilemap at the current cursor position. The four `wStringBuffer*` regions (WRAM) hold dynamically computed strings — gym leader names, item counts, whatever the calling script loaded before invoking `writetext`. See `docs/text-system.md` for the full placeholder reference.

### 9.1.4 The Variable-Width Font (VWF)

Prism renders player and Pokémon names with a *variable-width font*. The entry point is `PlaceVWFString` in `home/vwf.asm`. It:

1. Optionally copies the source string to `wDecompressScratch2` if it originates in ROM (the VWF renderer writes kerned tiles back into a scratch buffer).
2. Calls `_PlaceVWFString` (banked) which renders each glyph at its natural pixel width into `wDecompressScratch`.
3. Copies the result to VRAM via `Get2bpp` or `Get1bpp` depending on the `b` option flags.

The distinction between 2bpp and 1bpp is important: overworld name labels use 1bpp tiles (monochrome, shared with the font atlas), while battle name plates may use 2bpp for colour-capable rendering. The VWF engine lives in a banked section precisely because its scratch space (`wDecompressScratch`, a 4 KiB WRAM region also used by map decompression) must be accessed without disturbing the current WRAM bank.

Text speed (fast/mid/slow) is enforced by `PrintLetterDelay` in `home/print_text.asm`. It reads the speed bits from `wOptions`, sets `wTextDelayFrames`, and loops calling `DelayFrame` + `GetJoypad` — bailing early if A or B is pressed. Pressing A/B mid-scroll is therefore not a special code path; it is just the normal joypad poll falling through with the early-exit branch taken.

---

## 9.2 Menus & UI

### 9.2.1 The Generic Menu Driver

Most menus in Prism share a single cursor driver rooted in `home/menu.asm`. The key sequence is:

1. **`LoadMenuHeader`** — copies a `wMenuHeader` record from the caller's data, pushes a window backup onto the tilemap stack.
2. **`VerticalMenu`** — draws the box, places item labels via `PlaceVerticalMenuItems`, calls `ApplyTilemap`, then loops on `DoMenuJoypadLoop`.
3. **`CloseWindow`** — restores the saved tilemap region.

The `wMenuHeader` record (copied by `CopyMenuHeader`) describes the bounding box in tile coordinates, the VRAM tile destination for OBJ tiles, and the default selected item. `StandardMenuHeader` (a constant record in the file) is the fallback for the two-row dialogue YES/NO box:

```asm
StandardMenuHeader:
    db $40       ; tile backup region
    db 0, 0      ; top-left corner (tile coords)
    db 17, 19    ; bottom-right corner
    dw 0         ; OBJ tile address
    db 1         ; default option (1-indexed)
```

`VerticalMenu` returns with `a` holding the chosen item index, carry clear on selection and set on B-button cancel. It calls `MenuClickSound` before returning, so callers never need to remember to play the sound themselves.

### 9.2.2 The Scrolling List Widget

When a list is longer than the visible area — the party screen, the bag, the move list — Prism uses `_InitScrollingMenu` and `_ScrollingMenu` from `engine/scrolling_menu.asm`. The init sequence:

```asm
_InitScrollingMenu::
    call _InitScrollingMenuNoBGMapUpdate
    call ApplyTilemap
    call ConsumeGenericDelay
    xor a
    ldh [hBGMapMode], a
    ld [wGenericDelay], a
    ret
```

`_ScrollingMenu` then loops on `ScrollingMenuJoyAction`, which delegates to `_DoMenuJoypadLoop` and interprets d-pad up/down as cursor movement, A as selection, and B as cancel. The display is refreshed by `ScrollingMenu_InitDisplay`, which temporarily sets `NO_TEXT_SCROLL` in `wOptions` to suppress the per-letter delay while repainting item labels, then restores the original value.

The scrolling menu's extra power over the basic vertical menu is that it supports an **item-switch mode** (`ScrollingMenu_ValidateSwitchItem`) for the party reordering screen, and an optional function-3 callback (`ScrollingMenu_CheckCallFunction3`) invoked after each display refresh — used by, e.g., the bag to update the item description.

### 9.2.3 Major Screens — A Map

The four primary menu screens accessed from the start menu each have their own engine module:

| Screen | Primary file | Notes |
|--------|-------------|-------|
| Start menu | `engine/start_menu.asm` | Dispatches to the four sub-screens |
| Party screen | `engine/pokemon/party_menu.asm` | Uses scrolling menu + stat summaries |
| Bag / Pack | `engine/items/bag.asm` | Category tabs + scrolling item list |
| Pokédex | `engine/pokedex/pokedex.asm` | Search, sort, owned/seen flags |
| Town map | `engine/town_map.asm` | Tilemap-based landmark cursor |
| Naming screen | `engine/pokemon/name_mon.asm` | VWF + keyboard grid |
| Stats screen | `engine/pokemon/stats_screen.asm` | Multi-page flips; graph bars |

All of them follow the same pattern: `LoadMenuHeader` (or an equivalent direct tilemap setup), a local `_DrawScreen` subroutine that writes to `wTilemap` (the shadow tilemap in WRAM), `ApplyTilemap` to push the shadow to VRAM, and then a joypad loop. The tilemap shadow (`wTilemap`, a 20×18-tile WRAM buffer) is described in Chapter 6. All UI rendering writes there first; the hardware BG map is updated only during or just after VBlank.

---

## 9.3 The Audio Driver

### 9.3.1 Driver Structure and Channels

Prism runs a four-channel Game Boy audio driver ticked once per frame from the VBlank interrupt. The thin `home/audio.asm` layer exposes stable entry points (`PlayMusic`, `PlayMusic2`, `UpdateSound`, `FadeToMapMusic`) that push registers, call the banked implementation `_PlayMusic` / `_UpdateSound_SkipMusicCheck` via `bankpushcall`, and return:

```asm
PlayMusic::
    push hl
    push de
    push bc
    push af
    bankpushcall _PlayMusic, PlayMusic_BankPush
    jr PopOffRegsAndReturn
```

The actual driver state machine lives in a banked ROMX section (searched under `audio/`). It processes four hardware channels: **CH1** (square with sweep), **CH2** (square), **CH3** (custom wave), and **CH4** (noise). Each active channel tracks a pointer into its music-command stream, a tempo counter, and per-channel flags.

Music files wire up channels with the `channel` and `channelcount` macros:

```asm
; macros/sound.asm
MACRO channelcount
nchannels = \1 - 1
ENDM
MACRO channel
    dn (nchannels << 2), \1 - 1
    dw \2
nchannels = 0
ENDM
```

`channelcount N` declares how many channels follow; each `channel ID, label` emits a two-byte header that pairs the hardware channel index with the ROM address of the command stream.

### 9.3.2 Music Commands

The music command set is defined entirely through macros in `macros/sound.asm`. Every macro emits an opcode byte (assigned by a sequential `enum`) followed by operands. A representative selection:

| Macro | Opcode | Operands | Effect |
|-------|--------|----------|--------|
| `note dur, pitch` | — | 1 byte (nibble pair) | Play a note |
| `notetype` | `$d8` | length byte + optional intensity | Set note length and envelope |
| `octave N` | `notetype_cmd - N` | — | Set current octave (0–8) |
| `tempo val` | `$da+2` | 2-byte big-endian | Set global tempo |
| `vibrato delay, extent` | `vibrato_cmd` | 2 bytes | Enable pitch vibrato |
| `dutycycle d0,d1,d2,d3` | `sound_duty_cmd` | 1 byte packed | Duty-cycle sequence for CH1/2 |
| `volume val` | `volume_cmd` | 1 byte | Set channel volume |
| `panning tracks` | `panning_cmd` | 1 byte | Left/right mix |
| `slidepitchto dur, oct, pitch` | `slidepitchto_cmd` | 3 bytes | Pitch slide |
| `restartchannel addr` | `restartchannel_cmd` | 2-byte address | Loop back |

`note` itself is just `dn (\1), (\2) - 1` — a packed nibble — rather than a full opcode. Notes are inlined into the stream; the driver reads them as data when the opcode byte falls in the normal data range, below `$d8`. This lets music data be extremely dense: a typical bar of four quarter-notes fits in four bytes.

### 9.3.3 SFX

Sound effects use the same command set and the same driver, but are loaded on top of music channels with a priority mechanism. `togglesfx` (`togglesfx_cmd`) mutes the music channel for the duration. Short SFX are emitted with the `sound` macro:

```asm
; macros/sound.asm
MACRO sound
    note \1, \2        ; duration + pitch nibbles
    db \3              ; intensity
    dw \4              ; frequency
ENDM
```

### 9.3.4 Pokémon Cries and DED Compression

Pokémon cries are not music-command streams — they are **PCM audio data** compressed with a scheme called **DED** (*D*elta-*E*ncoded *D*ata, stored as a Huffman-coded delta stream). Two entry points handle cries:

- `PlayCry` (`home/cry.asm`) — plays and waits for the cry to finish.
- `PlayStereoCry2` / `PlayFaintingCry2` — non-blocking variants; `PlayFaintingCry2` additionally pitch-shifts the cry down by scaling `wCryPitch` by 90% for the pitch and 11% for the length, giving the characteristic drooping wail.

`LoadCryHeader` returns carry set if the species uses a DED cry (flagged by `$ff` in the header's first byte), clear if it uses the legacy Crystal-style frequency/pitch header. On the DED path, `PlayDEDCry` in `home/ded.asm` is called:

```asm
PlayDEDSamples::
    call StackCallInBankB
    call WriteDEDTreeToWRAM
    ld a, [hli]    ; length low
    ld e, a
    ld a, [hli]    ; length high
    ld d, a
    ld a, 8
    ldh [hCurSampVal], a
    ld c, 1        ; initialize bit counter
    ld a, (1 << rTAC_ON) | rTAC_16384_HZ
    ldh [rTAC], a  ; timer drives sample output
```

`WriteDEDTreeToWRAM` writes a small Huffman decode tree into WRAM as executable code — the tree is literally self-modifying machine instructions (`JR C`, `JP C`, `LD B, n`, `RET`) generated from the compressed tree structure. The timer interrupt fires at 16 384 Hz; each interrupt pops one decoded sample nibble and writes it to the wave channel (`rWave*`). The result is 4-bit PCM output at roughly 8 kHz, adequate for recognisable Pokémon cries while fitting in a few hundred bytes per species.

`cry_header` in `macros/sound.asm` encodes either the legacy three-byte header or the DED variant (flagged by a `$ff` sentinel and a `dba` bank+address pointer).

---

## 9.4 The Graphics Pipeline

### 9.4.1 Source Assets and Compression

Tile graphics live under `gfx/` as PNG files; the build system converts them to Game Boy **2bpp** (background and sprite tiles, 2 bits per pixel, 16 bytes per 8×8 tile) or **1bpp** (font tiles, 1 bit per pixel, 8 bytes per tile) using the `rgbgfx` tool. Most are then LZ-compressed. The LZ macros in `macros/lz.asm` define the authoring vocabulary:

```asm
; macros/lz.asm
lzdata   <byte [, byte ...]>          ; literal bytes (up to 1024)
lzrepeat <count>, <value> [, <value>] ; repeat one or two bytes
lzzero   <count>                      ; repeat $00
lzcopy   normal|flipped|reversed, <count>, <address>  ; back-reference
lzend                                 ; $ff terminator
```

The `_lzcmd` helper emits either a 1-byte header (`(type << 5) | (count - 1)` for counts ≤ 32) or a 2-byte long header (`$e0 | (type << 2) | high_count`, then low byte) for counts up to 1024. `lzcopy flipped` XORs every bit of each copied byte — handy for mirrored sprite sheets where the pixel content is the same but the bit-planes are inverted. `lzcopy reversed` walks the source pointer backward, exploiting run symmetry.

`gfx.asm` (the root graphics include) assembles the sub-includes that reference these compressed binaries:

```asm
INCLUDE "gfx/pics.asm"
INCLUDE "gfx/ow_sprites.asm"
INCLUDE "gfx/font.asm"
; ... etc.
```

Each sub-include binds a label to an `INCBIN` of the `.2bpp.lz` or `.1bpp.lz` file. For Pokémon front/back sprites the `pokepic` tool (Chapter 10) handles the PNG→2bpp conversion and applies a sprite-specific palette table before compression. The Chapter 10 tooling section covers the full build pipeline in detail.

### 9.4.2 Uploading Tiles to VRAM

Decompressed tile data must be transferred to VRAM only while the LCD is off or during HBlank/VBlank. `home/video.asm` provides the low-level primitives:

- **`DMATransfer`** — triggers a GBC H-DMA transfer (`rHDMA5`) for bulk copies, setting `hDMATransfer` to zero on completion and returning carry.
- **`UpdateBGMapBuffer`** — copies pending 16×8-tile blocks from `wBGMapBuffer` to the actual BG-map VRAM locations listed in `wBGMapBufferPtrs`. It reads `hBGMapUpdate` and `rVBK` to switch VRAM banks as needed, writing both tile-index (`VBK=0`) and attribute (`VBK=1`) planes in a single pass.

```asm
UpdateBGMapBuffer::
    ldh a, [hBGMapUpdate]
    and a
    ret z               ; nothing pending → early out
    ldh a, [rVBK]
    push af
    ld hl, wBGMapBufferPtrs
    ld sp, hl           ; use SP as a fast pop-pointer into the address list
    ld hl, wBGMapPalBuffer
    ld de, wBGMapBuffer
    ; ... paired 16×8 block copies follow
```

This function is called from VBlank ISR context. Using `sp` as a pointer into `wBGMapBufferPtrs` is an intentional trick for fast sequential reads during the time-critical VBlank window.

The tilemap shadow (`wTilemap`) is pushed to VRAM by `ApplyTilemap` (in `home/tilemap.asm`), which iterates over dirty rows and queues them into `wBGMapBuffer` for the next `UpdateBGMapBuffer` call.

### 9.4.3 Palette Upload

CGB palettes are stored in `wBGPals` and `wOBPals` (WRAM bank 5, at `5:d080` and `5:d0c0` respectively — 8 palettes × 4 colors × 2 bytes = 64 bytes each). `UpdatePals` in `home/palettes.asm` writes both banks to the hardware registers `rBGPD` and `rOBPD`:

```asm
ForceUpdateCGBPals::
    ld a, BANK(wBGPals)
    ldh [rSVBK], a          ; switch to WRAM bank 5
    ld hl, wBGPals
    ld a, %10000000         ; auto-increment, start at index 0
    ldh [rBGPI], a
    lb bc, 4, LOW(rBGPD)
.bgp
    rept 2 palettes
        ld a, [hli]
        ldh [c], a
    endr
    dec b
    jr nz, .bgp
    ; ... same for wOBPals → rOBPD
```

The `%10000000` write to `rBGPI` sets the auto-increment bit, so every subsequent write to `rBGPD` advances the hardware's internal palette index automatically. The driver pushes all 64 BG palette bytes in a tight loop of `rept 2 palettes … endr` — unrolled to avoid branch overhead. After writing, `hCGBPalUpdate` is cleared. The higher-level `ApplyPals` function (banked, referenced from `home/palettes.asm`) computes the actual RGB values from the game's logical palette tables before calling `ForceUpdateCGBPals`. Chapter 6 covers how time-of-day and permission-based palette selection feed into `wBGPals`.

### 9.4.4 Overworld Sprite Animations

The overworld sprite engine (`engine/sprite_anims.asm`) drives the NPC walk cycles and player step frames. Each overworld sprite has an OAM entry (`wSprites`, shadowed and flushed by `ForcePushOAM` via the DMA stub at `hPushOAM`) and an animation state machine that steps through tile-index sequences on a frame counter. `PushOAM` in `home/video.asm` checks `hOAMUpdate` before firing the `hPushOAM` DMA — so callers can suppress OAM updates during screen transitions by clearing the flag.

The tile-index sequences themselves come from the `gfx/ow_sprites/` 2bpp sheets. Each direction (up, down, left, right) has three frames: stand, step-left, step-right. The sprite engine selects the correct tile offset based on the facing byte in the NPC's object struct and the low bit of a walk-frame counter.

---

## 9.5 Reference: Key Files

| File | Contents |
|------|---------|
| `macros/charmap.asm` | `ctxtmap` definitions; all control-code byte assignments; Huffman patterns |
| `macros/text.asm` | `ctxt`, `text`, `line`, `para`, `cont`, `done`, `text_far`, `text_jump`, `start_asm` |
| `home/text.asm` | `TextBox`, `SpeechTextBox`, `TextControlCodeJumptable`, all placeholder handlers |
| `home/print_text.asm` | `PrintLetterDelay`, `PrintNum`, `PrintBCDNumber` |
| `home/vwf.asm` | `PlaceVWFString` — variable-width font renderer |
| `home/menu.asm` | `LoadMenuHeader`, `VerticalMenu`, `GetMenu2`, `CopyMenuHeader` |
| `engine/scrolling_menu.asm` | `_InitScrollingMenu`, `_ScrollingMenu`, scrolling list widget |
| `home/audio.asm` | `PlayMusic`, `PlayMusic2`, `UpdateSound`, `FadeToMapMusic` |
| `macros/sound.asm` | `note`, `notetype`, `octave`, `tempo`, `channel`, `channelcount`, `cry_header` |
| `home/cry.asm` | `PlayCry`, `PlayFaintingCry2`, `PlayStereoCry2` |
| `home/ded.asm` | `PlayDEDCry`, `PlayDEDSamples`, `WriteDEDTreeToWRAM` |
| `macros/lz.asm` | `lzdata`, `lzrepeat`, `lzzero`, `lzcopy`, `lzend` |
| `gfx.asm` | Root graphics include — ties together all `gfx/` sub-includes |
| `home/video.asm` | `PushOAM`, `DMATransfer`, `UpdateBGMapBuffer` |
| `home/palettes.asm` | `UpdatePals`, `ForceUpdateCGBPals`, `ForceUpdateCGBPalsIfMapSetupWarp` |
| `engine/sprite_anims.asm` | Overworld NPC walk-cycle state machine |

---

## Where to Next

Chapter 10 — *Tooling & Debugging* — lifts the lid on everything that runs *before* the assembler: `rgbgfx` and `pokepic` converting PNGs to 2bpp, the Python `prism-dev`/`prism-sym` devtools for inspecting WRAM live in an emulator, the `DEBUG_MODE` build flag and the `/patch/` bspcomp framework, and how `make nodebug` orchestrates the whole chain from source tree to flashable ROM.
