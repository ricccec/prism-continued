# Chapter 6 — Colour, Light & Loading

*The palette knows what time it is, and the map loader knows what order things must happen in.*

---

## 6.1 Where Chapter 5 Left Off

Chapter 5 ended at the last indirection in the rendering chain:

```
pal_slot (0–7)  →  4 RGB colors  (from palette system — see Chapter 6)
```

The attribute table tells each tile *which* of the eight background palette slots to draw from. This chapter explains how those eight slots get their actual RGB555 colors — and how the whole question depends on the map's permission byte and the current time of day.

The second half of the chapter turns to loading: how the engine assembles a live map from raw data, one atomic step at a time, using what is effectively a tiny bytecode interpreter.

---

## Part A — Colour & Light

## 6.2 The Two-Layer Palette System

The GBC hardware exposes eight background palette registers. Each holds four RGB555 colors. At any given moment, tile slot 0 draws from BG palette 0, tile slot 1 from BG palette 1, and so on — the attribute table byte is a direct hardware index.

Prism's overworld uses all eight slots simultaneously. Assigning RGB colors to them is a two-step calculation, both steps implemented in `LoadMapPals` (`engine/color.asm`):

1. **Permission → color table**: The map's permission byte (bits 0–2 of primary-header byte 2) selects one of four named color tables — `OutdoorColors`, `IndoorColors`, `DungeonColors`, or `Perm5Colors`.
2. **Color table row → palette indices**: The current time-of-day selects a row from the chosen table. Each row contains eight **palette indices** — one per BG slot — into `TilesetBGPalette`.
3. **Palette index → RGB555 quad**: Each palette index addresses a four-color entry in `TilesetBGPalette`, which is the label for the included file `tilesets/bg.pal`.

The full lookup in source:

```asm
; engine/color.asm — LoadMapPals (abridged)
    ld a, [wPermission]
    and 7
    ld e, a
    ld d, 0
    ld hl, .TilesetColorsPointers
    add hl, de
    add hl, de             ; index into the 8-entry pointer table (2 bytes/entry)
    ld a, [hli]
    ld h, [hl]
    ld l, a                ; hl → selected color table (OutdoorColors, etc.)
    ld a, [wTimeOfDayPal]
    and 3
    add a
    add a
    add a                  ; multiply by 8 (one row = 8 index bytes)
    add l
    ld l, a
    adc h
    sub l
    ld h, a                ; hl/de → the 8 palette-index bytes for this ToD row
    ; ...
    ld b, 8
.outer_loop
    ld a, [de]             ; read one palette index
    ; multiply by 8 to get byte offset into TilesetBGPalette
    ld l, a
    ld h, 0
    add hl, hl
    add hl, hl
    add hl, hl
    ld de, TilesetBGPalette
    add hl, de             ; point at the 8-byte (4-color) palette entry
    ; copy 8 bytes (4 × RGB555) into wOriginalBGPals
    ld c, 1 palettes
.inner_loop
    ld a, [de]
    inc de
    ld [hli], a
    dec c
    jr nz, .inner_loop
    ; advance to next slot
    inc de
    dec b
    jr nz, .outer_loop
```

The pointer table that routes permissions to color tables:

```asm
.TilesetColorsPointers
    dw .OutdoorColors ; permission 0 (unused)
    dw .OutdoorColors ; TOWN
    dw .OutdoorColors ; ROUTE
    dw .IndoorColors  ; INDOOR
    dw .DungeonColors ; CAVE
    dw .Perm5Colors   ; PERM_5
    dw .IndoorColors  ; GATE
    dw .DungeonColors ; DUNGEON
```

---

## 6.3 The Color Tables in Detail

Each color table is a 4×8 byte matrix: four rows (one per time-of-day slot) × eight palette indices per row. The four time-of-day values are `MORN` (0), `DAY` (1), `NITE` (2), and `DARKNESS` (3), defined in `constants/wram_constants.asm`.

```asm
; engine/color.asm
.OutdoorColors
    db $00, $01, $02, $28, $04, $05, $06, $07 ; morn
    db $08, $09, $0a, $28, $0c, $0d, $0e, $0f ; day
    db $10, $11, $12, $29, $14, $15, $16, $17 ; nite
    db $18, $19, $1a, $1b, $1c, $1d, $1e, $1f ; dark

.IndoorColors
    db $20, $21, $22, $23, $24, $25, $26, $07 ; morn
    db $20, $21, $22, $23, $24, $25, $26, $07 ; day
    db $10, $11, $12, $13, $14, $15, $16, $07 ; nite
    db $18, $19, $1a, $1b, $1c, $1d, $1e, $07 ; dark

.DungeonColors
    db $00, $01, $02, $03, $04, $05, $06, $07 ; morn
    db $08, $09, $0a, $0b, $0c, $0d, $0e, $0f ; day
    db $10, $11, $12, $13, $14, $15, $16, $17 ; nite
    db $18, $19, $1a, $1b, $1c, $1d, $1e, $1f ; dark
```

A few things are worth noticing:

- **Slot 3 outdoors is special.** Outdoor morn and day rows both use palette index `$28` for slot 3 (a water/sky variant), and nite uses `$29`. Dungeon maps use `$03`/`$0b`/`$13`/`$1b` — no special-cased slot. This is where outdoor water gets its daylight shimmer and nite-time deepening.

- **Indoor morn = indoor day.** Both rows are identical (`$20`–`$26`, `$07`). Artificial light doesn't change by morning vs. afternoon. Nite and dark do shift, because even indoor maps darken at night — the engine reuses the outdoor nite/dark palette rows (`$10`–`$1e`) for indoor rooms.

- **Slot 7 is pinned for IndoorColors.** All four rows end with `$07`, pulling from the fixed "white+black" pair used for text windows and UI borders. Outdoor maps let slot 7 fade with the sun; indoor maps keep it constant so menus remain legible.

`TilesetBGPalette` (the label at the start of `tilesets/bg.pal`) is a flat sequence of 4-color palettes, each 8 bytes. The valid index range is `$00`–`$29`, and `bg.pal` is laid out in sections matching the outdoor time-of-day bands: morn palettes at indices `$00`–`$07`, day at `$08`–`$0f`, nite at `$10`–`$17`, dark at `$18`–`$1f`, indoor-specific at `$20`–`$26`, and the special water/sky entries at `$28`–`$29`.

---

## 6.4 Time of Day from the RTC

`wTimeOfDayPal` (address `$d841`) holds the current time-of-day slot: 0 = MORN, 1 = DAY, 2 = NITE, 3 = DARKNESS. It is written by `UpdateTimeOfDayPal` in `engine/timeofdaypals.asm`:

```asm
UpdateTimeOfDayPal::
    call UpdateTime
    ld a, [wTimeOfDay]
    ld [wCurTimeOfDay], a
    call GetTimePalette
    ld [wTimeOfDayPal], a
    ret
```

`UpdateTime` (`home/time.asm`) reads the MBC3 real-time clock registers (`MBC3RTC`), applies the in-game epoch offset stored in `wRTCBase*`, and produces calendar values: `wCurYear`, `wCurMonth`, `wCurDay`, `hHours`, `hMinutes`, `hSeconds`. It is guarded by `CheckEngine ENGINE_TIME_ENABLED` — if the engine flag is not set, the call returns immediately, leaving `wTimeOfDay` unchanged.

`GetTimeOfDay` (`engine/rtc.asm`) then does something unusual for a Game Boy game: it computes the actual local sunrise and sunset times from the in-game latitude (`RIJON_LATITUDE EQU 33.2`), the earth's axial tilt (`EARTH_AXIAL_TILT EQU 23.43712`), and the current day of the year. The result is a dynamic sunrise offset (`wSunriseOffset`) that shifts the morn/day/nite boundaries seasonally — summer gives longer days, winter gives longer nights. The time boundaries come back as one of `MORN`, `DAY`, or `NITE` written into `wTimeOfDay`. `DARKNESS` is never produced by `GetTimeOfDay` directly; it is set by a different path.

`GetTimePalette` (`engine/timeofdaypals.asm`) maps `wTimeOfDay` → palette slot via a jump table:

```asm
GetTimePalette:
    ld a, [wTimeOfDay]
    jumptable
.TimePalettes
    dw .MorningPalette
    dw .DayPalette
    dw .NitePalette
    dw .DarknessPalette

.MorningPalette
    ld a, [wTimeOfDayPalset]
    and %00000011   ; bits 1–0
    ret
.DayPalette
    ld a, [wTimeOfDayPalset]
    and %00001100   ; bits 3–2
    srl a
    srl a
    ret
; ... (NitePalette and DarknessPalette follow the same pattern)
```

The returned value (0–3) is not the MORN/DAY/NITE constant itself — it is a **brightness level** (0 = fully bright, 3 = darkest) extracted from `wTimeOfDayPalset`. This indirection through `wTimeOfDayPalset` is what enables the `DARKNESS`/Flash special case.

---

## 6.5 The Dark-Cave / Flash Special Case

`wMapTimeOfDay` (offset 156 in `wram.asm`) holds the *map's own* time-of-day override, copied from primary-header byte 7 during map load. Value 4 means "dark cave" — the map is unlit by default regardless of the real-world clock.

`ReplaceTimeOfDayPals` (`engine/timeofdaypals.asm`) reads `wMapTimeOfDay` and builds `wTimeOfDayPalset`:

```asm
ReplaceTimeOfDayPals:
    ld hl, .BrightnessLevels
    ld a, [wMapTimeOfDay]
    cp 4                    ; dark cave?
    jr z, .DarkCave
    and 7
    add l
    ld l, a                 ; index into BrightnessLevels
    ld a, [hl]
    ld [wTimeOfDayPalset], a
    ret

.DarkCave
    ld a, [wStatusFlags2]
    bit 0, a                ; Flash used?
    jr nz, .UsedFlash
    ld a, %11111111         ; all brightness-level 3 — maximum dark
    ld [wTimeOfDayPalset], a
    ret
.UsedFlash
    ld a, %10101010         ; all brightness-level 2 — partially lit
    ld [wTimeOfDayPalset], a
    ret

.BrightnessLevels
    brightlevel 3, 2, 1, 0  ; outdoor: morn/day/nite/dark brightness
    brightlevel 1, 1, 1, 1  ; uniform indoor
    brightlevel 2, 2, 2, 2  ; dim
    brightlevel 0, 0, 0, 0  ; fully bright
    brightlevel 3, 3, 3, 3  ; maximum dark
    brightlevel 3, 2, 1, 0  ; (repeated entries)
    brightlevel 3, 2, 1, 0
    brightlevel 3, 2, 1, 0
```

The `brightlevel` macro packs four 2-bit values into one byte: `(\1 << 6) | (\2 << 4) | (\3 << 2) | \4`. For a normal outdoor map (`.BrightnessLevels` index 0), morning uses brightness 3 (darkest end of the morn palette spectrum), day uses 2, nite uses 1, and dark uses 0 — a somewhat counter-intuitive encoding where 0 = brightest palette index and 3 = darkest. A dark cave with no Flash sets all four time-of-day brightness levels to 3, so `GetTimePalette` always returns 3 regardless of the real clock, and the color tables index into the darkest palette row. Flash softens this to brightness 2, adding a partial illumination halo.

---

## 6.6 Runtime Palette Fades

Palettes are not recalculated only on map entry. The overworld loop calls `_TimeOfDayPals` (`engine/timeofdaypals.asm`) once per frame. If `wTimeOfDay` has changed since the last frame — meaning the clock has ticked past a boundary — it fades the palettes smoothly:

```asm
_TimeOfDayPals::
    ; (check wTimeOfDayPalFlags bit 7 — forced pals skip this)
    ld a, [wTimeOfDay]
    ld hl, wCurTimeOfDay
    cp [hl]
    jr z, .dontchange       ; no time boundary crossed
    ld [wCurTimeOfDay], a
    call GetTimePalette
    ld hl, wTimeOfDayPal
    cp [hl]
    jr z, .dontchange       ; same palette as before (brightness unchanged)
    ld [wTimeOfDayPal], a
    ; ... fade via GetTimePalFade ...
    call _UpdateTimePals
```

`GetTimePalFade` produces a seven-step brightness ramp table:

```asm
.cgbfade
    db %11111111, %11111111, %11111111  ; fully lit
    db %11111110, %11111110, %11111110
    db %11111001, %11111001, %11111001
    db %11100100, %11100100, %11100100
    db %10010000, %10010000, %10010000
    db %01000000, %01000000, %01000000
    db %00000000, %00000000, %00000000  ; fully dark
```

Each row is three bytes — one BG mask, one OBJ mask, one spare — and the transition steps through them with a two-frame delay between each via `ConvertTimePalsIncHL`/`ConvertTimePalsDecHL`. The result is that the shift from afternoon to evening is a gradual purple wash, not a sudden cut.

---

## 6.7 Special-Tileset Palette Overrides

Some areas are visually distinct enough that the standard permission/time-of-day system cannot express them. `LoadSpecialMapPalette` — called first inside `LoadMapPals` — intercepts four tileset IDs before the general logic runs:

```asm
; engine/color.asm — LoadSpecialMapPalette
LoadSpecialMapPalette:
    ld a, [wTileset]
    cp TILESET_TRAINER_HOUSE
    ld hl, .battle_room_palette
    jr z, .load_eight_palettes      ; fixed — no time-of-day variation
    cp TILESET_TUNOD
    ld hl, .tunod_palette
    jr z, .load_time_of_day_palettes
    cp TILESET_ESPO_FOREST
    ld hl, .espo_forest_palette
    jr z, .load_time_of_day_palettes
    cp TILESET_OLCAN_ISLE
    jr z, .olcan_isle               ; may use tunod.pal or olcan_isle.pal
    and a
    ret                             ; carry clear → caller uses standard path

.olcan_isle
    ld hl, .tunod_palette
    ld a, [wMapGroup]
    cp GROUP_OLCAN_ISLE
    jr nz, .load_time_of_day_palettes
    ld a, [wMapNumber]
    cp MAP_OLCAN_ISLE
    jr nz, .load_time_of_day_palettes
    ld hl, .olcan_isle_palette
.load_time_of_day_palettes
    ld a, [wTimeOfDayPal]
    and 3
    ld bc, 8 palettes
    rst AddNTimes               ; skip forward by ToD × 8 palette-entries
.load_eight_palettes
    ld a, BANK(wOriginalBGPals)
    ld de, wOriginalBGPals
    ld bc, 8 palettes
    call FarCopyWRAM
    scf                         ; carry set → LoadMapPals skips standard path
    ret

.battle_room_palette: INCLUDE "tilesets/battle_tower.pal"
.tunod_palette:       INCLUDE "tilesets/tunod.pal"
.espo_forest_palette: INCLUDE "tilesets/espo_forest.pal"
.olcan_isle_palette:  INCLUDE "tilesets/olcan_isle.pal"
```

Key behaviors:

| Tileset | Palette file | Time-of-day variation |
|---|---|---|
| `TILESET_TRAINER_HOUSE` | `tilesets/battle_tower.pal` | No — fixed dark palette |
| `TILESET_TUNOD` | `tilesets/tunod.pal` | Yes — ×8 offset by `wTimeOfDayPal` |
| `TILESET_ESPO_FOREST` | `tilesets/espo_forest.pal` | Yes |
| `TILESET_OLCAN_ISLE` | `tilesets/olcan_isle.pal` (on the island itself) or `tunod.pal` (elsewhere) | Yes |

The Olcan Isle case is interesting: the same tileset is used for both the island map and a few overworld maps in Tunod. The check compares `wMapGroup`/`wMapNumber` against the exact Olcan Isle map constants and picks the specialized `.pal` only on the island, falling back to `tunod.pal` for other maps that happen to share the tileset.

When `LoadSpecialMapPalette` sets carry, `LoadMapPals` jumps over the general permission/color-table logic entirely:

```asm
LoadMapPals:
    call LoadSpecialMapPalette
    jr c, .got_pals        ; carry set → skip to OBJ palettes
    ; ... general path: TilesetColorsPointers, TilesetBGPalette ...
.got_pals
    ; load OBJ palettes, roof palette, etc.
```

---

## Part B — Map Loading

## 6.8 Loading a Map Is a Bytecode Program

The most important design insight in the map loading system is that "entering a map" is not a single function call with a long body — it is the execution of a *small bytecode program*. Each transition type (warp, connection, fly, door, etc.) has its own program, and those programs share a common instruction set of 48 atomic operations.

This design surfaces in `engine/map_setup.asm`. The entry point is `RunMapSetupScript`:

```asm
RunMapSetupScript::
    ldh a, [hMapEntryMethod]
    and $f
    dec a                     ; entry methods start at $f1; subtract to get 0-based index
    ld c, a
    ld b, 0
    ld hl, MapSetupScripts
    add hl, bc
    add hl, bc                ; each entry is 2 bytes (dw)
    ld a, [hli]
    ld h, [hl]
    ld l, a                   ; hl → the selected script
    jp ReadMapSetupScript
```

`hMapEntryMethod` (`hram.asm` offset 39) holds a byte written by the warp/connection/fly code before invoking the setup system. The constants are defined in `constants/map_setup_constants.asm`, starting at `$f1`:

| Value | Constant | Meaning |
|---|---|---|
| `$f1` | `MAPSETUP_WARP` | Through a warp tile / cave entrance |
| `$f2` | `MAPSETUP_CONTINUE` | Resuming from a save |
| `$f3` | `MAPSETUP_RELOADMAP` | In-place reload (after a menu) |
| `$f4` | `MAPSETUP_TELEPORT` | Escape Rope or teleport |
| `$f5` | `MAPSETUP_DOOR` | Through a door tile |
| `$f6` | `MAPSETUP_FALL` | Fell through a hole |
| `$f7` | `MAPSETUP_CONNECTION` | Scrolled into an adjacent map |
| `$f8` | `MAPSETUP_LINKRETURN` | Returned from link trade/battle |
| `$f9` | `MAPSETUP_TRAIN` | Exited the Magnet Train |
| `$fa` | `MAPSETUP_SUBMENU` | Returned from a menu |
| `$fb` | `MAPSETUP_BADWARP` | Fallback for undefined warps |
| `$fc` | `MAPSETUP_FLY` | Used Fly |
| `$fd` | `MAPSETUP_BATTLE_TOWER` | Battle Tower entry |

`RunMapSetupScript` strips the high nibble, subtracts one to make it zero-indexed, and indexes `MapSetupScripts` — a table of `dw` pointers. Each pointer leads to a sequence of `mapsetup` macro invocations.

---

## 6.9 The Bytecode Mechanics

The `mapsetup` macro emits a single byte:

```asm
MACRO mapsetup
    db (\1SetupCommand - MapSetupCommands) / 3
ENDM

mapsetup_end EQUS "db $FF"
```

Every named command (`EnableLCD`, `LoadBlockData`, etc.) has an entry in `MapSetupCommands`. Each entry is a three-byte far pointer (`dba`), which is one bank byte plus a two-byte address. The macro computes the command's byte offset from the start of the table and divides by 3, yielding a 0-based command index. At runtime the interpreter multiplies back by 3 and does a far call.

The interpreter is a tight loop:

```asm
_ReadMapSetupScript_loop:
    push hl
    ld c, a
    ld b, 0
    ld hl, MapSetupCommands
    add hl, bc
    add hl, bc
    add hl, bc              ; bc × 3 = byte offset of far pointer
    call FarPointerCall     ; call the function in the appropriate ROM bank
    pop hl
ReadMapSetupScript:
    ld a, [hli]             ; read next command byte from script
    cp -1                   ; $ff = mapsetup_end
    jr nz, _ReadMapSetupScript_loop
    ret
```

`ReadMapSetupScript` reads a byte, checks for `$ff` terminator, and either returns or loops. One byte per step, 48 possible commands. There are no operands: every `mapsetup` command is a pure function, parameterized entirely by WRAM state at the time it executes.

---

## 6.10 Walking Through `MapSetupScript_Warp`

`MAPSETUP_WARP` is the canonical path — what happens when the player walks through a door or into a cave. Its script:

```asm
MapSetupScript_Warp:
    mapsetup DisableLCD
    mapsetup MapSetup_Sound_Off
    mapsetup LoadSpawnPoint
    mapsetup LoadMapAttributes
    mapsetup RunCallback_05_03
    mapsetup SpawnPlayer
    mapsetup RefreshPlayerCoords
    mapsetup GetCoordOfUpperLeftCorner
    mapsetup LoadBlockData
    mapsetup BufferScreen
    mapsetup LoadGraphics
    mapsetup LoadMetatilesTilecoll
    mapsetup LoadMapTimeOfDay
    mapsetup LoadObjectsRunCallback_02
    mapsetup LoadMapPalettes
    mapsetup ForceUpdateCGBPalsIfMapSetupWarp
    mapsetup EnableLCD
    mapsetup SpawnInFacingDown
    mapsetup RefreshMapSprites
    mapsetup PlayMapMusic
    mapsetup FadeInMusic
    mapsetup FadeInPalettes
    mapsetup ActivateMapAnims
    mapsetup LoadWildMonData
    mapsetup_end
```

The ordering discipline is strict and intentional:

**Phase 1 — Lockout (steps 1–2).** `DisableLCD` turns off the display before any VRAM writes happen. On real hardware, writing to VRAM while the PPU is drawing produces garbage pixels. Sound is also stopped immediately — there is a brief silence during every warp.

**Phase 2 — Data loading (steps 3–12).** `LoadSpawnPoint` sets `wMapGroup`/`wMapNumber` and related warp coordinates. `LoadMapAttributes` reads the new map's primary and secondary headers, populates `wTileset`, `wPermission`, `wMapWidth`, `wMapHeight`, and the script/event/warp tables. `LoadBlockData` decompresses the block grid and fills the 3-block border (Chapter 5, §5.5). `LoadGraphics` decompresses the 2bpp tile GFX into VRAM. `LoadMetatilesTilecoll` fills `wDecompressedMetatiles`, `wDecompressedAttributes`, and `wDecompressedCollision` in WRAM bank 5 (Chapter 5, §5.6).

**Phase 3 — Palette and time of day (steps 13–16).** `LoadMapTimeOfDay` calls `ReplaceTimeOfDayPals` (which sets `wTimeOfDayPalset` based on the new map's permission and dark-cave flag) and `UpdateTimeOfDayPal` (which writes `wTimeOfDayPal`). This must happen *before* `LoadMapPalettes` because `LoadMapPals` reads `wTimeOfDayPal` to select the correct color table row. `ForceUpdateCGBPalsIfMapSetupWarp` pushes the computed palettes into the hardware registers.

**Phase 4 — Re-enable and animate (steps 17–24).** `EnableLCD` turns the display back on. Now it is safe: tile GFX is in VRAM, palette registers are set, the tile map is valid. `FadeInPalettes` performs the animated fade-up from black. `ActivateMapAnims` starts the per-frame animation callbacks. `LoadWildMonData` prepares the wild encounter tables for the new zone.

The key invariant: **nothing writes to VRAM or palette hardware between `DisableLCD` and `EnableLCD`.** Any violation would produce visible corruption for the one or two frames the LCD takes to re-arm. The script structure enforces this by design — all VRAM-writing steps are sandwiched between the two LCD control commands.

---

## 6.11 Contrasting `MapSetupScript_Connection`

Walking into an adjacent map by scrolling to the map edge uses `MAPSETUP_CONNECTION`:

```asm
MapSetupScript_Connection:
    mapsetup SuspendMapAnims
    mapsetup EnterMapConnection
    mapsetup LoadMapAttributes
    mapsetup RunCallback_05_03
    mapsetup RefreshPlayerCoords
    mapsetup LoadBlockData
    mapsetup LoadTilesetHeader
    mapsetup SaveScreen
    mapsetup LoadObjectsRunCallback_02
    mapsetup FadeToMapMusic
    mapsetup LoadMapPalettes
    mapsetup QueueLandmarkSignAnim
    mapsetup _UpdateTimePals
    mapsetup LoadWildMonData
    mapsetup UpdateRoamMons
    mapsetup ActivateMapAnims
    mapsetup_end
```

Three things are conspicuously absent compared to `MapSetupScript_Warp`:

1. **No `DisableLCD` / `EnableLCD`.** The connection transition is seamless — the player is visibly scrolling across the edge. Blanking the screen would produce a visible flash. Instead, the new map data is written while the old display is still active. This is safe only because the connection transition does not reload tile GFX into VRAM; the two adjacent maps are expected to share a tileset (or at least share the currently loaded tile set). The block grid update (`LoadBlockData`) writes only to WRAM, not VRAM.

2. **`LoadTilesetHeader` instead of `LoadGraphics` + `LoadMetatilesTilecoll`.** This reloads the tileset header WRAM record (so `wTileset`, `wTilesetBank`, etc. are current for the new map) but does *not* decompress metatiles, attributes, or tile GFX. Those tables remain in WRAM and VRAM from the previous map. This is the performance optimization that makes connection transitions instantaneous — the expensive decompression work is skipped.

3. **`SaveScreen` instead of `BufferScreen`.** `BufferScreen` writes a fresh screen snapshot. `SaveScreen` preserves whatever the screen currently shows (the player is still mid-step), because the connection transition reuses the live BG layer.

The connection transition's correctness depends on the 3-block border filled by `FillMapConnections` during `LoadBlockData`. That border was already loaded from the adjacent map *before* the connection trigger fired — it was pre-fetched during the previous map's load. When `EnterMapConnection` updates `wMapGroup`/`wMapNumber` and `LoadBlockData` decompresses the new map's full block grid, the border is just extended. No visual discontinuity occurs because the screen edge tiles were already correct.

This is the preparation that Chapter 5 named but deferred: the 3-block border's second purpose is specifically to enable instant connection transitions. Chapter 7 covers how the connection trigger fires and how `EnterMapConnection` identifies the correct alignment between the two maps' edges.

---

## 6.12 The `mapsetup` Command Table

`MapSetupCommands` maps each command byte to a `dba` far pointer. The table starts at byte 0 with `EnableLCD` and currently ends at byte `$30` with `LoadMetatilesTilecoll`:

| Byte | Command | Notes |
|---|---|---|
| `$00` | `EnableLCD` | |
| `$01` | `DisableLCD` | |
| `$0a` | `LoadBlockData` | Decompresses block grid; fills border strips |
| `$0e` | `LoadGraphics` | Tile GFX → VRAM (only in full-warp paths) |
| `$0f` | `LoadTilesetHeader` | Header only; used in connection path |
| `$10` | `LoadMapTimeOfDay` | Sets `wTimeOfDayPalset`, `wTimeOfDayPal` |
| `$11` | `LoadMapPalettes` | Calls `LoadMapPals`; computes 8 BG palettes |
| `$1a` | `LoadMapAttributes` | Parses primary + secondary headers |
| `$1c` | `ClearBGPalettes` | |
| `$1d` | `FadeOutPalettes` | |
| `$1e` | `FadeInPalettes` | Animated fade from black |
| `$2b` | `_UpdateTimePals` | Used in connection path for live ToD refresh |
| `$30` | `LoadMetatilesTilecoll` | Metatile/attr/collision → WRAM bank 5 |

`mapsetupcommand` is defined in `constants/map_setup_constants.asm` as:

```asm
MACRO mapsetupcommand
\1SetupCommand::
    dba \1
ENDM
```

The label `\1SetupCommand` is what `mapsetup \1` references at assemble time to compute the byte offset. The linker resolves both the label and the `dba` pointer; RGBDS's cross-bank call convention handles bank switching at runtime via `FarPointerCall`.

---

## 6.13 Summary: The Full Picture

The path from "player steps on a warp tile" to "new map is visible" now has no hidden steps:

1. Collision code detects the `$7x`-family collision byte, looks up the warp destination, writes `hMapEntryMethod = MAPSETUP_WARP`.
2. `RunMapSetupScript` indexes `MapSetupScripts` and calls `ReadMapSetupScript` with `MapSetupScript_Warp`.
3. The interpreter executes 24 commands in order, enforcing the LCD-disable / VRAM-write / LCD-enable discipline.
4. `LoadMapTimeOfDay` sets `wTimeOfDayPalset` via `ReplaceTimeOfDayPals` (handling dark caves and Flash), then `wTimeOfDayPal` via `GetTimePalette`.
5. `LoadMapPalettes` calls `LoadSpecialMapPalette` first; if carry is not set, it uses `wPermission` → `TilesetColorsPointers` → one of `OutdoorColors`/`IndoorColors`/`DungeonColors` → eight palette indices → eight entries in `TilesetBGPalette` → `wOriginalBGPals`.
6. `FadeInPalettes` animates from black to the live palette state.
7. From this point, `_TimeOfDayPals` monitors the RTC each frame and smoothly fades between time-of-day slots as the game clock progresses.

---

## 6.14 Reference: Key Symbols

| File | Symbol | Role |
|---|---|---|
| `engine/color.asm` | `LoadMapPals` | Orchestrates both palette layers |
| `engine/color.asm` | `LoadSpecialMapPalette` | Tileset-specific `.pal` override |
| `engine/color.asm` | `TilesetBGPalette` | Label pointing at `tilesets/bg.pal` |
| `engine/color.asm` | `.OutdoorColors`, `.IndoorColors`, `.DungeonColors` | 4×8 color index tables |
| `engine/timeofdaypals.asm` | `ReplaceTimeOfDayPals` | Builds `wTimeOfDayPalset` (brightness levels, cave/Flash) |
| `engine/timeofdaypals.asm` | `GetTimePalette` | `wTimeOfDayPalset` → final palette row index |
| `engine/timeofdaypals.asm` | `_TimeOfDayPals` | Per-frame clock-change check + fade |
| `engine/timeofdaypals.asm` | `GetTimePalFade` | 7-step brightness ramp for time transitions |
| `engine/rtc.asm` | `GetTimeOfDay` | RTC hours/minutes → `wTimeOfDay` (seasonal sunrise) |
| `home/time.asm` | `UpdateTime` | Reads MBC3 RTC registers; populates `hHours`, etc. |
| `engine/map_setup.asm` | `RunMapSetupScript` | Entry point; indexes `hMapEntryMethod` → `MapSetupScripts` |
| `engine/map_setup.asm` | `MapSetupScript_Warp` | Full VRAM-reload path |
| `engine/map_setup.asm` | `MapSetupScript_Connection` | Lightweight scrolling-transition path |
| `engine/map_setup.asm` | `ReadMapSetupScript` | Bytecode interpreter loop |
| `engine/map_setup.asm` | `MapSetupCommands` | 48-entry far-pointer table |
| `constants/map_setup_constants.asm` | `MAPSETUP_*`, `mapsetup`, `mapsetupcommand` | Constants and macros |
| `constants/wram_constants.asm` | `MORN`, `DAY`, `NITE`, `DARKNESS` | Time-of-day enum (0–3) |
| `tilesets/bg.pal` | — | Master BG palette data, indices `$00`–`$29` |
| `tilesets/tunod.pal`, `espo_forest.pal`, `olcan_isle.pal`, `battle_tower.pal` | — | Special-area palette overrides |
| `wram.asm` | `wTimeOfDayPal` (`$d841`) | Current time-of-day slot (0–3) |
| `wram.asm` | `wTimeOfDayPalset` | Packed 4×2-bit brightness level byte |
| `wram.asm` | `wMapTimeOfDay` | Per-map ToD override from primary header |
| `hram.asm` | `hMapEntryMethod` | Entry method byte; drives `RunMapSetupScript` |

---

## Where to Next

You now understand how the GBC's eight background palette registers get their colors (permission → color table → brightness level → `TilesetBGPalette`), how the real-time clock feeds seasonal time-of-day calculations, and how the map loader executes an ordered bytecode program that enforces the LCD-disable / VRAM-write / LCD-enable contract on every warp. One thing was deliberately left open: the connection trigger that sets `hMapEntryMethod = MAPSETUP_CONNECTION`, the warp resolution that resolves `MAPSETUP_WARP`'s spawn point, and the map script callbacks that fire during `LoadMapAttributes`. Those are all driven by the overworld scripting VM — the subject of **Chapter 7**.
