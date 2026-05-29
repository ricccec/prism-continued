# Codebase Map

A directory-by-directory guide to every major file. Use this when you need to
find where a system lives before reading code.

---

## `home/` — ROM Bank 0 Library

All code here is callable from any ROM bank via `farcall` / `predef`.
If a function needs to be available game-wide, it lives here.

| File | What it does |
|------|-------------|
| `init.asm` | Hardware init on boot (stack, LCD, memory clear) |
| `highhome.asm` | Very first code run; jumps to init |
| `farcall.asm` | Far-call trampoline (switches banks, calls, restores) |
| `bankswitch.asm` | Low-level bank register write |
| `predef.asm` | Predefined function dispatch table |
| `jumptable.asm` | Generic indexed jump dispatch |
| `joypad.asm` | Button state polling and held/pressed tracking |
| `lcd.asm` | LCD on/off, mode waits, DMA copy |
| `vblank.asm` | VBlank interrupt — sprite DMA, audio tick |
| `video.asm` | Screen mode helpers, tilemap DMA |
| `palettes.asm` | CGB palette upload routines |
| `screen.asm` | Screen clear, blank, transition helpers |
| `tilemap.asm` | Tilemap copy, scroll, coordinate utilities |
| `window.asm` | Window layer helpers |
| `copy.asm` | `CopyBytes`, `CopyData`, `FillBytes` — memory copy primitives |
| `print_text.asm` | Text engine entry point (variable-width font) |
| `text.asm` | Character decode, text box draw |
| `vwf.asm` | Variable-width font rendering |
| `get_names.asm` | Look up Pokémon/move/item/trainer names by index |
| `string.asm` | String copy, compare, length utilities |
| `menu.asm` | Generic cursor menu driver |
| `scripting.asm` | Map script bytecode interpreter (entry point) |
| `map.asm` | Load map, run map callbacks |
| `map_objects.asm` | Spawn and update overworld NPCs/objects |
| `movement.asm` | Player and NPC step/turn engine |
| `player_movement.asm` | Player-specific movement and collision |
| `pokemon_data.asm` | Read/write Pokémon party/box struct fields |
| `item.asm` | Add/remove/check items in bag |
| `trainer.asm` | Load trainer data, initiate trainer battle |
| `array.asm` | Array search and fill helpers |
| `random.asm` | Linear-feedback RNG |
| `math.asm` | 8/16-bit multiply, divide, shift |
| `sine.asm` | Sine table lookup |
| `delay.asm` | Wait N frames |
| `cry.asm` | Play Pokémon cry |
| `battle.asm` | Battle engine entry (farcall shim) |
| `pokedex_flags.asm` | Seen/caught bitfield read/write |
| `hp_pal.asm` | HP bar color selection (green/yellow/red) |
| `decompress.asm` | LZ decompression |
| `ded.asm` | DED audio playback decoder |
| `audio.asm` | Audio driver tick, channel management |
| `fade.asm` | Screen fade in/out |
| `game_time.asm` | Play-time counter (hours/minutes) |
| `handshake.asm` | Link cable handshake |
| `count_events.asm` | Count set event flags in a range |
| `stone_queue.asm` | Evolution stone pending queue |
| `stopwatch.asm` | Frame-accurate stopwatch |
| `flag.asm` | Generic bit flag set/clear/test |
| `weekday.asm` | Day-of-week from RTC |
| `rtc.asm` | Real-time clock read/write |
| `serial.asm` | Serial port I/O |
| `crash.asm` | Crash handler — display registers, halt |

---

## `engine/` — Banked Game Logic

Loaded into banked ROM; called via `farcall`/`predef` from `home/`.

### Overworld / Player
| File | What it does |
|------|-------------|
| `overworld.asm` | Main overworld loop |
| `player_movement.asm` | Walk, run, bike, surf collision |
| `map_setup.asm` | Load map graphics, tilesets, palettes |
| `map_objects.asm` | Overworld sprite tick (banked) |
| `events.asm` | Tile event dispatch (step-on, interact) |
| `scripting.asm` | Script command implementations |
| `tile_events.asm` | Warp, ledge, water, ice tile handlers |
| `warp_connection.asm` | Map connection scrolling |
| `spawn_player.asm` | Place player on map after warp |
| `spawn_points.asm` | Whiteout/heal spawn table |
| `sprites.asm` | Sprite allocation and priority |
| `sprite_anims.asm` | Overworld animation frames |
| `objects.asm` | Object struct management |
| `walk_follow.asm` | Follow-NPC movement AI |

### Menus / UI
| File | What it does |
|------|-------------|
| `main_menu.asm` | New game / continue / options screen |
| `startmenu.asm` | Start-button menu |
| `selectmenu.asm` | Select-button shortcut menu |
| `party_menu.asm` | Party selection screen |
| `mon_menu.asm` | Per-Pokémon action menu |
| `pack.asm` | Bag/pack screen |
| `options_menu.asm` | Options screen |
| `scrolling_menu.asm` | Generic scrollable list widget |
| `stats_screen.asm` | Pokémon summary screen |
| `trainer_card.asm` | Trainer card display |
| `namingscreen.asm` | Character entry screen |
| `name_player.asm` | Name player flow |
| `intro_menu.asm` | Introduction/prof. Oak screen |
| `title.asm` | Title screen |
| `credits.asm` | End credits |

### Pokémon Mechanics
| File | What it does |
|------|-------------|
| `pokemon_data.asm` | Banked Pokémon struct accessors |
| `pokemon_structs.asm` | Party/box struct layout constants |
| `evolve.asm` | Evolution check and trigger |
| `evolution_animation.asm` | Evolution visual effect |
| `breeding.asm` | Egg generation and daycare logic |
| `daycare.asm` | Daycare NPC interactions |
| `pokedex.asm`, `pokedex2.asm` | Pokédex display |
| `gender.asm` | Gender determination from DVs |
| `show_pokemon_info.asm` | Stat display helpers |
| `experience.asm` | EXP gain and level-up |
| `happiness.asm` | Friendship delta calculations |
| `pokerus.asm` | Pokérus spread logic |
| `pop_mon.asm` | Remove Pokémon from party |
| `move_mon.asm` | Reorder party Pokémon |
| `switch_party_mons.asm` | Party ↔ box transfer |

### Items / Moves
| File | What it does |
|------|-------------|
| `items.asm` | Item use dispatch |
| `item_effects.asm` | Per-item effect implementations |
| `field_moves.asm` | HM field move handlers (Cut, Surf …) |
| `field_items.asm` | Use item from bag in field |
| `tmhm.asm`, `tmhm2.asm` | TM/HM teach flow |

### Battle Interface
| File | What it does |
|------|-------------|
| `battle_start.asm` | Initiate wild / trainer battle |
| `wildmons.asm` | Wild encounter table lookup |
| `pokepic.asm` | Pokémon sprite load/decompress |
| `playerpic.asm` | Player sprite in battle |

### Utility
| File | What it does |
|------|-------------|
| `math.asm`, `math16.asm` | Extended arithmetic |
| `color.asm` | Palette manipulation |
| `fade.asm` | Banked fade helpers |
| `print_number.asm` | Render integers to screen |
| `print_mon_stats.asm` | Stats bar rendering |
| `hp_bars.asm`, `anim_hp_bar.asm` | HP bar draw/animate |
| `stable_rng.asm` | Seeded RNG for reproducible results |
| `rtc.asm` | RTC helpers (banked) |
| `landmarks.asm` | Town map landmark lookup |
| `town_map.asm` | Town map screen |
| `save.asm` | Save game read/write |
| `heal_party.asm` | Full heal all party members |
| `link.asm`, `link_trade.asm` | Link cable trade flow |
| `debug_menu.asm` | Debug-mode cheat menu (excluded in nodebug) |
| `emulator_check.asm` | Detect emulator vs hardware |
| `crash_report.asm` | Extended crash info display |

---

## `battle/` — Battle Engine

| File / Dir | What it does |
|-----------|-------------|
| `initialize.asm` | Set up battle state for wild/trainer |
| `files.asm` | Includes for the whole battle subsystem |
| `music.asm` | Battle music start/stop |
| `misc.asm` | Miscellaneous battle helpers |
| `type_matchup.asm` | Type effectiveness table lookup |
| `used_move_text.asm` | "X used Y!" text rendering |
| `trainer_huds.asm` | Trainer-side HP/ball HUDs |
| `badge_boosts.asm` | Gym badge stat multipliers |
| `abilities.asm` | Ability trigger dispatch |
| `ability_names.asm` | Ability name strings |
| `ability_descriptions.asm` | Ability description strings |
| `consume_held_item.asm` | Trigger held-item consumption |
| `pickup.asm` | Pickup ability post-battle |
| `sliding_intro.asm` | Battle intro slide animation |
| `bg_effects.asm` | Battle background weather/special effects |
| `anim_objects.asm` | Move animation sprite objects |
| `anim_commands.asm` | Animation bytecode interpreter |
| `anim_gfx.asm` | Animation graphics data |
| `anims.asm` | All move animation scripts (~134KB) |
| `engine/` | Core battle logic split into subdirs: |
| `engine/core/` | Turn processing, damage calc |
| `engine/actions/` | Move/item/switch action handlers |
| `engine/abilities/` | Per-ability effect implementations |
| `engine/endturn/` | End-of-turn effects (burn, weather …) |
| `engine/experience/` | EXP and EV gain |
| `engine/finish/` | Battle end, prize money, Pokémon catch |
| `engine/link/` | Link battle synchronization |
| `engine/text/` | Battle text rendering |
| `engine/util/` | Shared battle utilities |
| `moves/` | Move data tables and effect function pointers |
| `ai/` | CPU trainer AI (move scoring, item use, switch) |

---

## `event/` — Special Events & Minigames

| File | What it does |
|------|-------------|
| `itemball.asm` | Overworld item pickup |
| `hidden_item.asm` | Hidden item detection (Itemfinder) |
| `elevator.asm` | Elevator floor select |
| `whiteout.asm` | Blackout / lose battle handler |
| `poisonstep.asm` | Step-poison tile damage |
| `slot_machine.asm` | Game Corner slot machine |
| `card_flip.asm`, `blackjack.asm`, `poker.asm`, `cardgames.asm` | Card minigames |
| `bingo.asm` | Bingo minigame |
| `memory_game.asm` | Memory card game |
| `park_minigame.asm` | Safari/park minigame |
| `pachisi.asm` | Pachisi board game |
| `battle_arcade.asm` | Battle Arcade facility |
| `battle_tower.asm` | Battle Tower facility |
| `qrcode.asm` | QR code scanner |
| `ballmaking.asm` | Apricorn ball crafting |
| `mining.asm`, `smelting.asm`, `jeweling.asm` | Crafting minigames |
| `daycare.asm` | Daycare interaction scripts |
| `bank.asm` | Pokémon bank / PC box |
| `judge.asm` | IV judge NPC |
| `fossil_puzzle.asm` | Fossil restoration puzzle |
| `halloffame.asm` | Hall of Fame recording |
| `time_machine.asm` | Time Machine (trade with Gen I/II) |
| `gold_tokens.asm` | Gold token economy |
| `spurge_gym.asm` | Spurge City gym puzzle |
| `magnet_train.asm` | Magnet Train travel |
| `name_rater.asm` | Name Rater NPC |

---

## `data/` — Game Data Tables

| Path | Contents |
|------|---------|
| `base_stats/` | One `.asm` file per Pokémon: HP/Atk/Def/SpA/SpD/Spe, types, abilities, egg groups |
| `base_stats.asm` | Pointer table for `base_stats/` entries |
| `evos_attacks.asm` | Evolution methods + level-up movesets per species |
| `evos_attacks_pointers.asm` | Pointer table for above |
| `movesets/` | Level-up learnsets (one file per species) |
| `tmhmlearnsets.asm` | TM/HM compatibility bitfields per species |
| `tmmoves.asm` | Which move each TM teaches |
| `egg_moves.asm` | Egg move pools per species |
| `pokedex/` | Pokédex entry text (species, height, weight, description) |
| `wild/` | Wild encounter tables per map/area |
| `landmarks/` | Landmark → map-coordinate mapping (for town map) |
| `map_objects.asm` | NPC/object definitions referenced by maps |
| `pokemon_names.asm` | 11-char species name strings |
| `sprite_headers.asm` | Overworld sprite dimension headers |
| `predefs.asm` | Predef function ID → address table |

---

## `constants/` — Numeric Constants

Every ID used in the codebase is defined here as an `EQU` constant.

| File | Defines |
|------|---------|
| `pokemon_constants.asm` | `SPECIES_*` IDs (1–251 + new) |
| `move_constants.asm` | `MOVE_*` IDs |
| `item_constants.asm` | `ITEM_*` IDs |
| `type_constants.asm` | `NORMAL`, `FIRE`, … type IDs |
| `trainer_constants.asm` | `TRAINER_*` class IDs |
| `map_constants.asm` | `MAP_*` IDs and `SPAWN_*` constants |
| `map_dimension_constants.asm` | Map width/height per map group |
| `landmark_constants.asm` | `ROUTE_*`, city landmark IDs |
| `event_flags.asm` | `EVENT_*` bitfield indices |
| `engine_flags.asm` | `ENGINE_*` persistent flag indices |
| `music_constants.asm` | `MUSIC_*` song IDs |
| `sfx_constants.asm` | `SFX_*` sound effect IDs |
| `cry_constants.asm` | `CRY_*` Pokémon cry IDs |
| `battle_constants.asm` | Battle state flags, move effect IDs |
| `ability_constants.asm` | `ABILITY_*` IDs |
| `script_constants.asm` | Script command byte values |
| `gfx_constants.asm` | Sprite/palette slot IDs |
| `collision_constants.asm` | Tile collision type IDs |
| `wram_constants.asm` | Named offsets into Pokémon structs |
| `misc_constants.asm` | Miscellaneous single-use constants |

---

## `macros/` — Code-Generation Macros

| File | Key macros |
|------|-----------|
| `enum.asm` | `enum_start`, `enum`, `const_def`, `const`, `shift_const` |
| `map.asm` | `warp_def`, `person_event`, `signpost`, `coord_event` |
| `event.asm` | `setflag`, `resetflag`, `checkflag`, script flow helpers |
| `movement.asm` | `step_left`, `step_right`, `turn_head`, `end_movement` |
| `text.asm` | `text`, `line`, `cont`, `done`, `para` text macros |
| `basestats.asm` | `base_stats` struct builder |
| `trainer.asm` | `trainer_party`, `trainer_mon` struct helpers |
| `move_effect.asm` | `move_effect` struct builder |
| `sound.asm` | `music_cmd`, `note`, `sound_header` channel macros |
| `charmap.asm` | Character encoding map (text → bytes) |
| `pals.asm` | `RGB` color macro and palette helpers |
| `lz.asm` | `INCBIN_LZ` — include LZ-compressed binary |
| `predef.asm` | `predef`, `predef_jump` far-call helpers |
| `rst.asm` | `farcall`, `callab`, `callfar` restart shims |
| `flag.asm` | `setflag`, `resetflag`, `checkflag` wrappers |
| `wram.asm` | `def_wram_byte`, `def_wram_word` RAM layout helpers |
| `varblocks.asm` | Variable-size data block macros |
| `debug_menu.asm` | Debug menu entry helpers |

---

## `utils/` — Build Tools (C programs)

| Binary | Source | Purpose |
|--------|--------|---------|
| `scaninc` | `scaninc.c` | Walk `INCLUDE` deps for Makefile dependency tracking |
| `pokepic` | `pokepic.c` | Convert Pokémon PNG framesheet → 2BPP + palette + frame data |
| `lzcomp` | `lz/` submodule | LZ compress arbitrary binary data |
| `bankends` | `bankends.c` | Parse `.map` file and report free space per ROM bank |
| `rendergifs` | `rendergifs.c` | Render map block data to GIF previews |
| `ipspatch` | `ipspatch.c` | Create/apply IPS patches |
| `gbspatch` | `gbspatch.c` | Patch GBS offset table into release ROM |
| `gbstrim` | `gbstrim.c` | Trim GBS file to correct length |
| `bspcomp` | `bsp/` submodule | BSP patch creation/application |
| `qrconv` | `qrconv.c` | Convert QR ASM descriptor → 1BPP tile data |
| `pngtrim` | `pngtrim.c` | Strip trailing transparent rows from PNGs |
| `asm2bin.sh` | shell | Assemble a standalone `.asm` to raw binary |
| `coll2bin.sh` | shell | Compile collision data to binary |

---

## `contents/` — Linker Scripts

| File | Role |
|------|------|
| `contents.link` | Master script; includes all others |
| `romx.link` | Maps 117 ROMX banks → named sections |
| `homebank.link` | ROM bank 0 section layout |
| `wram.link` | WRAM section layout |
| `sram.link` | SRAM section layout |
| `gbs.link` | GBS-format section layout |
| `bank_ends.txt` | Generated: free bytes per bank (from `make freespace`) |
