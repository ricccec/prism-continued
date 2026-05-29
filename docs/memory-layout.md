# Memory Layout

Game Boy memory map for Pokémon Prism. All addresses are for the Game Boy
memory bus. Source of truth: `wram.asm` (includes `hram.asm`, `vram.asm`,
`sram.asm`).

---

## Game Boy Address Space

| Range | Region | Used for |
|-------|--------|---------|
| `$0000–$3fff` | ROM Bank 0 | `home/` runtime library |
| `$4000–$7fff` | ROM Bank 1–$75 (switchable) | `engine/`, `battle/`, `maps/`, data |
| `$8000–$9fff` | VRAM | Tile data, tile maps |
| `$a000–$bfff` | SRAM (save RAM) | Saved game data |
| `$c000–$cfff` | WRAM0 | Fixed work RAM (always mapped) |
| `$d000–$dfff` | WRAM1 | Banked work RAM (banks 1–7 on GBC) |
| `$fe00–$fe9f` | OAM | Sprite attribute table |
| `$ff00–$ff7f` | I/O registers | Hardware control (`gbhw.asm`) |
| `$ff80–$fffe` | HRAM | High RAM (stack, fast variables) |

---

## VRAM (`$8000–$9fff`)

Defined in `vram.asm`.

| Address | Section | Contents |
|---------|---------|---------|
| `$8000–$8fff` | Tile Data 0 | Battle / menu sprites (BG + OBJ tile set 0) |
| `$9000–$97ff` | Tile Data 1 | Font tiles and overworld BG tiles |
| `$9800–$9bff` | Tile Map 0 | Background tile map |
| `$9c00–$9fff` | Tile Map 1 | Window tile map |

On GBC, VRAM has two banks. Bank 1 holds CGB attribute data (palette, priority,
flip bits) mirroring bank 0's tile maps.

---

## WRAM0 (`$c000–$cfff`) — Always Mapped

| Symbol | Rough range | Contents |
|--------|-------------|---------|
| `wAudioBuffer` | `$c000–` | Audio driver channel structs (8 channels) |
| `wMusicVolume` | | Current music volume |
| `wMapData` | | Loaded map block data |
| (general engine vars) | `$c000–$cfff` | See `wram.asm` for exact layout |

---

## WRAM1 (`$d000–$dfff`) — Key Symbols

These are the most commonly referenced variables. Full list in `wram.asm`.

### Player & Overworld
| Symbol | Meaning |
|--------|---------|
| `wPlayerName` | Player name string (11 bytes + terminator) |
| `wRivalName` | Rival name string |
| `wPlayerID` | Player's trainer ID (2 bytes) |
| `wPlayerMoney` | Money in BCD (3 bytes) |
| `wPlayerCoins` | Game Corner coins (2 bytes) |
| `wMap` | Current map ID |
| `wMapGroup` | Current map group |
| `wXCoord`, `wYCoord` | Player tile coordinates |
| `wPlayerDirection` | Facing direction |
| `wWalkCounter` | Step counter for encounters |
| `wTimeOfDay` | Current time-of-day slot (MORN/DAY/NITE) |
| `wJoyInput` | Raw joypad state this frame |
| `wJoyPressed` | Newly-pressed buttons this frame |
| `wJoyHeld` | Held buttons |

### Party
| Symbol | Meaning |
|--------|---------|
| `wPartyCount` | Number of Pokémon in party (0–6) |
| `wPartySpecies` | Party species list (7 bytes, $ff terminated) |
| `wPartyMons` | Party Pokémon structs (6 × `MON_DATA_LENGTH` bytes) |
| `wPartyMonOT` | OT names for party Pokémon |
| `wPartyMonNicks` | Nicknames for party Pokémon |

### Bag
| Symbol | Meaning |
|--------|---------|
| `wNumItems` | Item count in items pocket |
| `wItems` | Item pocket entries (ID, qty pairs) |
| `wNumBalls` | Pokéball count |
| `wBalls` | Ball pocket entries |
| `wNumKeyItems` | Key item count |
| `wKeyItems` | Key item entries |
| `wTMsHMs` | TM/HM possession bitfield |

### Battle
| Symbol | Meaning |
|--------|---------|
| `wBattleMode` | 0 = no battle, 1 = wild, 2 = trainer |
| `wBattleType` | Battle type flags |
| `wBattleMonSpecies` | Active Pokémon species (player side) |
| `wEnemyMonSpecies` | Active Pokémon species (enemy side) |
| `wBattleMon` | Player's active battle Pokémon struct |
| `wEnemyMon` | Enemy's active battle Pokémon struct |
| `wCurMoveNum` | Selected move slot (0–3) |
| `wCurMove` | Move ID being executed |
| `wPlayerTurnOrder` | Player moves first/second this turn |
| `wDamage` | Calculated damage this hit |
| `wTurn` | Turn counter |

### Flags
| Symbol | Meaning |
|--------|---------|
| `wEventFlags` | Main event flag bitfield (~256 flags) |
| `wVisitedSpawns` | Visited heal-point bitfield |
| `wEngineFlags` | Persistent engine state flags |
| `wPokedexOwned` | Pokédex caught bitfield |
| `wPokedexSeen` | Pokédex seen bitfield |
| `wBadges` | Johto badge bitfield |
| `wPrismBadges` | Prism-region badge bitfield |

### Misc
| Symbol | Meaning |
|--------|---------|
| `wGameTimeHours` | Play time hours (2 bytes, BCD) |
| `wGameTimeMinutes` | Play time minutes |
| `wGameTimeSeconds` | Play time seconds |
| `wGameTimeFrames` | Play time frame counter |
| `wSavedAtLeastOnce` | Flag: save has occurred |
| `wOptions` | Options byte (text speed, battle anim, …) |
| `wScriptBank`, `wScriptPos` | Current script execution pointer |

---

## SRAM (`$a000–$bfff`) — Save Data

Defined in `sram.asm`. Backed by cartridge battery.

| Section | Contents |
|---------|---------|
| `sSaveDataChecksum` | Checksum of save block |
| `sPlayerData` | Copy of key player WRAM vars |
| `sBox1–sBox14` | PC box Pokémon storage (14 boxes) |
| `sHallOfFameData` | Hall of Fame records |
| `sRTCStatus` | RTC calibration data |

---

## HRAM (`$ff80–$fffe`) — High RAM

Defined in `hram.asm`. Fastest accessible memory; used for interrupt-safe
variables and the stack.

| Symbol | Meaning |
|--------|---------|
| `hROMBank` | Shadow of currently mapped ROM bank |
| `hSRAMBank` | Shadow of currently mapped SRAM bank |
| `hVBlankCounter` | Frame counter (incremented each VBlank) |
| `hMapAnims` | Pending map animation requests |
| `hDMATransfer` | OAM DMA routine (copied here at boot) |
| `hJoyInput` | Raw joypad value from last read |
| `hAudioEnabled` | Audio on/off flag |
| `hPrintNum_*` | Scratch space for print_number |
| `hMathBuffer` | Scratch space for math routines |
| Stack (`$fffe` downward) | Call/interrupt stack |

---

## Accessing Variables from Assembly

```asm
; Load a byte
ld a, [wPartyCount]

; Load a 16-bit word
ld hl, wPlayerMoney
ld a, [hli]     ; low byte
ld b, [hl]      ; high byte

; Set a flag
ld a, [wBadges]
set BIT_BADGE1, a
ld [wBadges], a

; Far variable (different WRAM bank on GBC)
; Use GetPartyMonData / SetPartyMonData predef for party structs
```

### Bank switching
ROM bank switches go through `home/bankswitch.asm`:
```asm
ld a, BANK(SomeFunction)
rst SwitchToROMBank
call SomeFunction
```
The current bank is mirrored in `hROMBank` so it can be restored after an
interrupt.
