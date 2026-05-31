---
title: "Pokémon Prism — A Bedtime Read"
subtitle: "A gentle, one-hour tour through a 2 MB ROM"
author: "for the curious, the new, and the half-asleep"
---

# Pokémon Prism — A Bedtime Read

*A gentle, one-hour tour through a 2 MB ROM hack of Pokémon Crystal.*

---

## Prologue — A small magic

There is something quietly magical about a Game Boy cartridge. A piece of plastic the size of a matchbook, a little board inside, a chip with a million-something bytes etched into it, and yet — somehow — an entire region of the world, with towns and mountains and seas and the impossible animals you raised in it. Pokémon Crystal shipped in 2000 on exactly this kind of cartridge: two megabytes of read-only memory, thirty-two kilobytes of save RAM, a small battery to keep the time, and a real-time clock that ticked along whether the console was on or not. Open one and you'd see a circuit board, but the magic was somewhere else — in the careful arrangement of those two megabytes.

Pokémon Prism is, at its heart, a love letter to that arrangement. It is a *ROM hack*: a fan-made modification of Pokémon Crystal, built not by patching the original game's bytes but by reassembling it from a disassembly — a complete rewriting of Crystal's binary back into human-readable Game Boy assembly. From that disassembly the Prism developers grew a different game: new region, new story, new Pokémon, new minigames, new mechanics. The resulting `pokeprism_nodebug.gbc` file is still two megabytes, still runs on the original hardware, and still must obey every constraint Nintendo's engineers obeyed in 1999.

This document is meant to be read in roughly an hour, perhaps with a cup of tea, perhaps in bed. It is not a reference manual — those exist alongside it in this same `docs/` folder. It is closer to a guided walk through the building, pointing at the load-bearing walls and the strange little rooms, with enough technical detail to be real and enough metaphor to be enjoyable. By the end you should know, in shape if not in every line, how the codebase is laid out, where the major systems live, and how the whole thing fits together to become a game.

A small warning: assembly language is going to come up. It is not a programming language in the usual sense; it is the literal sequence of instructions the Game Boy's processor executes, dressed up in mnemonics like `ld`, `jp`, `farcall`. If you have never read it, do not worry — I will translate as we go. If you have, you'll see the patterns immediately. Either way, the goal is not to make you a Game Boy hacker tonight; it is to leave you, at the end, with a mental map you didn't have at the beginning.

So: a deep breath. We're going to step into the cartridge.

---

## Chapter 1 — The cartridge as a city

The Game Boy's processor — a custom 8-bit chip called the Sharp LR35902 — can only see 64 kilobytes of address space at a time. That's the entire universe, as far as the CPU is concerned: addresses from `$0000` to `$ffff`. Everything the game ever needs — code, graphics, sound, level data, scratch memory, the hardware control registers, the very screen itself — must live somewhere in that 64 KB window.

Two megabytes of cartridge ROM, however, is thirty-two times larger than that window. So how does a 2 MB game run on a 64 KB machine?

The answer, beautifully, is *banking*. The cartridge is divided into a stack of sixteen-kilobyte slices called *banks*. There are 128 of them, numbered `$00` through `$7f`. Bank `$00` is always visible at addresses `$0000–$3fff`. The other 127 banks share a single window at `$4000–$7fff`, and a control register in the cartridge's mapper chip decides which one is mapped in at any given moment. To call a piece of code in bank `$12`, you write the number `$12` to that register, and then the bytes you wanted appear at `$4000`. Want bank `$23` instead? Write `$23`. The processor never has to know — it just sees code at `$4000` and runs it.

If you imagine the cartridge as a city, bank zero is the central plaza — always there, always accessible, the place everyone meets. The other banks are neighborhoods that share one street corner: only one neighborhood can be "current" at a time, but you can swap which one with a single instruction. The mapper chip is the city's switchboard operator.

Pokémon Prism uses this architecture to its absolute fullest. The file `contents/romx.link`, a *linker script*, is the city plan: it tells the build system which sections of source code go into which banks. Reading it is like reading a real-estate map.

```
Banks $01–$12 : Code sections 1–18 (engine logic)
Banks $13–$1f : Code sections 19–31 + specialised modules
Banks $20–$35 : Map block data (per-map visual tiles)
Banks $36–$44 : Map scripts (event handlers)
Banks $45–$55 : Graphics (tilesets, overworld sprites, battle animations)
Banks $56–$65 : Audio (music tracks)
Banks $66–$75 : DED-compressed cry audio (split across 27 sections)
```

That's the entire ROM, on one page. Every byte the game ever runs is somewhere in this layout.

A few of those numbers deserve a pause. There are 461 maps in the game. Their *block data* — the actual tile-by-tile layout of every floor and route — fills 22 entire banks, from `$20` to `$35`. Their *scripts* — the code that runs when you step on a tile, talk to an NPC, push a button — fill another 15. The game's music takes 16 banks, and the sound effects and Pokémon cries another 16 on top of that. The game's *code*, by contrast — the actual logic that makes anything happen — fits in only 31 banks. Pokémon games, like most games, are mostly data. The engine is a small, dense machine surrounded by a vast amount of content.

It is worth noting that none of this was strictly *necessary* — a developer in 2000 could in principle have written a smaller game. The interesting choice is the way Prism uses the original Crystal's structure, with all its existing bank assignments and conventions, and gently extends it. The team did not redesign the cartridge; they expanded the city.

When you build the ROM, the linker — a program called `rgblink` — reads `contents/contents.link` and the other linker scripts it includes, and then it assigns every assembled section to its named bank. If a bank overflows by a single byte, the build fails. The Makefile target `make freespace` writes a file called `bank_ends.txt` reporting exactly how many free bytes remain in each bank. As of writing, several banks have only a few hundred bytes of slack. The city is densely packed.

If that gives you a slight chill of anxiety — adding one new song or one new map might require shuffling sections between banks like a real-estate puzzle — that's because it sometimes does. ROM hackers have, in this way, the same anxieties cartridge developers had a quarter century ago: how do I make this fit?

---

## Chapter 2 — Bank zero, the library

Of all 128 banks, bank zero is special, because it is the one place the CPU can always see, no matter what the bank switch register has been set to. So bank zero is where you put everything that needs to be callable from anywhere. In the Prism codebase, that is the directory called `home/`.

If the rest of the codebase is the city, `home/` is the public library. It contains the routines that any other code, in any other bank, must be able to call without ceremony. The reason is not philosophical but mechanical: when you're running code in bank `$23` and you want to jump to a function in bank `$45`, you can't just `call` it — the call instruction takes a 16-bit address, but you also need to swap the bank register first, and then *swap it back* when the function returns. That dance is implemented by a clever little routine called `farcall`, which lives in `home/farcall.asm`. And `farcall` itself has to live in bank zero, because anyone, in any bank, must be able to call it.

So `home/` is full of fundamental, game-wide primitives. Let me list a few, just to give you the flavor:

- `home/init.asm` — the very first code the cartridge runs at boot. It clears memory, sets up the stack, turns on the LCD, and hands control to the title screen.
- `home/bankswitch.asm` — the four-instruction routine that writes to the bank register. The smallest, most-called function in the game.
- `home/farcall.asm` and `home/predef.asm` — the two trampoline systems for cross-bank function calls. `farcall` is the manual, address-based version; `predef` is the indexed version that looks up the target function in a table.
- `home/joypad.asm` — reads the directional pad and buttons every frame, tracks which are newly pressed, which are held.
- `home/lcd.asm`, `home/vblank.asm`, `home/video.asm` — turn the screen on and off, wait for the safe drawing window between frames, DMA pixel data into video memory.
- `home/copy.asm` — the byte-copy primitives. `CopyBytes`, `CopyData`, `FillBytes`. Used hundreds of times across the game.
- `home/print_text.asm`, `home/text.asm`, `home/vwf.asm` — the text engine. `vwf` stands for *variable-width font*; Prism's font, unlike vanilla Crystal's, renders letters at their natural widths.
- `home/scripting.asm` — the bytecode interpreter that runs map scripts. We'll come back to scripts in Chapter 5.
- `home/random.asm` — the linear-feedback shift register that drives every random decision in the game, from wild encounters to critical hits to which way an NPC walks.
- `home/decompress.asm` and `home/ded.asm` — the runtime decompressors for LZ-packed graphics and DED-packed audio respectively.
- `home/crash.asm` — yes, there is a crash handler. If the CPU ever takes an unexpected interrupt or jumps into garbage, this routine catches it and prints the register state to the screen so a developer can see what went wrong.

The single most important thing to understand about `home/` is that it's a *library*, not a *flow*. There is no main loop in `home/`; you can't read top-to-bottom and learn what the game does. You can only look up *primitives*. The flow lives elsewhere — most of it in `engine/overworld.asm` and `engine/battle/...`, both of which we'll see in their own chapters.

There's a charming aesthetic detail worth noticing here. Many of the file names in `home/` are exactly the same as file names elsewhere in the codebase: `home/scripting.asm` and `engine/scripting.asm` are different files. The first is the bytecode dispatcher — the part that has to live in bank zero so it can be called from anywhere. The second is the implementations of the bytecode commands themselves, which can live in banked ROM and be loaded only when needed. That split — *dispatch in bank zero, implementation in a banked file* — is a recurring pattern in this codebase. Once you see it, you see it everywhere.

If you wanted to read just one file in `home/` to get a feel for the place, I'd suggest `home/init.asm`. It is the first code the Game Boy executes, and it is small enough to read in a sitting. You can follow, step by step, how a powered-off Game Boy becomes a running game: stack pointer set, audio off, video off, work RAM cleared, palettes initialised, save RAM checksummed, title screen scheduled. It is the gentle awakening of a small machine.

---

## Chapter 3 — The engine rooms

The directory called `engine/` is where the bulk of the game's logic lives. It is enormous. If `home/` is a library of about sixty files, `engine/` is a small town of its own: dozens of subdirectories, hundreds of `.asm` files, every major game system spread out into its own corner.

The engine is *banked* code — that is, it lives in ROM banks one through about eighteen, depending on which subsystem. From bank zero you reach into engine code via `farcall`. From bank to bank within the engine, you do the same. The bookkeeping is invisible to the source: you just write `farcall SomeFunction` and the assembler emits the necessary bank swap and call.

The engine subdivides cleanly into a handful of broad categories. Let me walk you through them.

**The overworld** lives in `engine/overworld.asm`, `engine/player_movement.asm`, `engine/map_setup.asm`, and a constellation of related files. This is the system that runs while you're walking around: it polls the joypad, decides whether to scroll the camera, animates the player and the NPCs, checks every tile for encounters, ledges, water, ice. The main loop here is a long state machine — you'd find yourself in `Overworld_PlayerInput`, then `PlayerStep`, then a check for a wild battle, then a check for a script trigger, then back to the top. Every step you take in the game is one iteration of this loop.

**The menus.** Almost every screen that isn't the overworld or a battle is a menu of some kind, and almost every menu lives in `engine/`. `main_menu.asm` handles the very first New Game / Continue / Options screen. `startmenu.asm` is the one that pops up when you press Start in the field. `pack.asm` is the bag. `party_menu.asm` is the party. `stats_screen.asm` is the summary screen for an individual Pokémon. `trainer_card.asm`, `pokedex.asm`, `town_map.asm` — each has its own file, its own draw routine, its own little local input loop. Menus are heavyweight in 8-bit games, because every screen you draw is a tilemap you have to fill, every cursor is a sprite you have to animate, every text box is a sequence of character codes you have to decode and render. The amount of code dedicated to menus is, frankly, startling, but it is also why the game *feels* responsive and modern.

**Pokémon mechanics.** This is the part most people associate with "the game". `evolve.asm` handles the check at the end of a battle for whether any of your Pokémon should evolve, and the trigger that begins the animation. `breeding.asm` and `daycare.asm` handle eggs. `experience.asm` runs the EXP gain math. `happiness.asm` adjusts friendship values. `pokerus.asm` spreads the contagious-good status. `pokedex.asm` runs the Pokédex screen. `gender.asm` reads a Pokémon's DVs to decide whether it's male or female. These files are not enormous — most are a few hundred lines — but together they implement the entire metagame.

**Battle interface.** Strictly speaking, the battle engine lives in its own folder, `battle/`, which we'll visit in the next chapter. But the *entry points* and a few important pieces — like `wildmons.asm`, the wild encounter table lookup — live in `engine/`. The actual battle code is so large it needs its own city.

**Utilities.** A lot of `engine/` is helper code. `math.asm` and `math16.asm` extend `home/math.asm` with multi-byte multiplication and division. `color.asm` builds palettes. `fade.asm` orchestrates fade-in and fade-out animations. `print_number.asm` renders integers (since text is one thing and numbers are another). `save.asm` is the file I keep coming back to — it implements the save game system, with checksumming, double-buffered redundancy, and migration handling. The save system is one of those quiet pieces of software that nobody ever thinks about unless it fails.

The thing to notice about `engine/` is that it is not very abstract. There is no inheritance hierarchy, no virtual methods, no polymorphism. There is also remarkably little duplication: each system lives in one place, with its data and its logic side by side, and it is called by name from the rest of the game. The codebase is large but readable in the way that a well-organised hardware store is large but findable — every shelf has a label.

If I were to recommend just one file in `engine/` to read, it would be `engine/save.asm`. It is self-contained, the algorithm is genuinely interesting (a journal-style write to one of two banks with checksum verification), and it teaches you, in microcosm, how a piece of state in the game survives a power-cycle.

---

## Chapter 4 — The stadium

The `battle/` directory is where Pokémon become Pokémon. It is the largest single subsystem in the codebase: a layered, mostly-self-contained engine that takes over the screen, runs its own loop, draws its own HUDs, plays its own music, and only returns control to the overworld when one side has fainted everything.

The top-level files are the seams between battle and the rest of the game:

- `battle/initialize.asm` — sets up battle state. Loads the trainer's party or the wild Pokémon, copies the player's party into battle-local memory, plays the intro animation, and starts the first turn.
- `battle/files.asm` — a giant include list that pulls in the rest of the battle subsystem. Treat it as a table of contents.
- `battle/type_matchup.asm` — the table that tells you Water is 2× super-effective on Fire, ½× on Grass, and so on. It is exactly the data you remember from the manual.
- `battle/used_move_text.asm` — the system that renders "Charizard used FLAMETHROWER!" on the screen.
- `battle/abilities.asm`, `battle/ability_names.asm`, `battle/ability_descriptions.asm` — abilities are a Gen-III concept; Prism backports them to Gen II, which is one of its most ambitious features.
- `battle/anims.asm` — *all* the move animation scripts. This file is around 134 kilobytes of bytecode, the size of an entire Pokémon Yellow ROM, just for the visual effects of moves. Each animation is a small program that spawns sprites, plays sound effects, fades the screen, draws shapes, then cleans up. Read a few of them and you'll start to see the same patterns: a brief setup, a spawn, a wait, a teardown.

Then there is the `battle/engine/` subdirectory, which is where the actual logic lives, split into a deliberate set of sub-subdirectories:

- `battle/engine/core/` — turn processing, damage calculation, hit checking, the central state machine. This is where a turn is conceptually a function: take both players' chosen actions, decide the order based on speed and priority, run the first action's effects, then the second's, then any end-of-turn effects, then back to the top.
- `battle/engine/actions/` — the handlers for the four things a player can do in a turn: use a move, use an item, switch Pokémon, or run. Each one is its own little program.
- `battle/engine/abilities/` — the per-ability effect implementations. *Static* makes contact moves paralyse 30 % of the time; that 30 %-check lives here.
- `battle/engine/endturn/` — burn damage, poison damage, leech-seed transfer, weather damage, status countdowns — all the things that tick at the end of a turn.
- `battle/engine/experience/` — EXP gain, EV gain, level-up math.
- `battle/engine/finish/` — what happens when a battle ends. Prize money for trainer victories, capture mechanics for wild Pokémon, the "win" / "lose" / "ran" branches.
- `battle/engine/link/` — link-cable battle synchronization, for trading and battling with another Game Boy over the cable.
- `battle/engine/text/` — battle-specific text rendering (with all its little tricks for the "..." animations and the move-name colouring).
- `battle/engine/util/` — shared helpers.

And there is `battle/moves/`, which is the data side: one table of move records (`moves.asm`), with each record specifying the move's effect ID, power, type, accuracy, PP, and effect chance, plus a parallel table (`move_effects_pointers.asm`) of function pointers — one per effect ID — that implements what the move actually *does*. *Quick Attack* and *Tackle* are both `EFFECT_NORMAL_HIT`; *Toxic* is `EFFECT_TOXIC`; *Thunder Wave* is `EFFECT_PARALYZE_HIT`. Adding a new move means writing a new effect handler and pointing the new move at it.

Finally there is `battle/ai/` — the CPU trainer's brain. It is small, but cleverer than it looks. The AI scores each candidate move for the current situation (effective type, current HP, status effects, etc.), applies trainer-specific bias parameters (a "Pokémaniac" picks somewhat randomly; an "Elite Four" member never wastes a turn), and then chooses. The same module also handles whether to use an item, whether to switch out, and which Pokémon to send next when one faints.

The battle engine is the part of the codebase most ROM-hackers tend to modify. It is also the part most likely to break in subtle ways when you change it — because the entire system is a tightly-balanced choreography between two parallel state machines (yours and the opponent's), and tugging on any thread can echo in unexpected places. The cautionary tale every Pokémon disassembly community shares is the bug where one player's status condition would inadvertently apply to the other side because of a missing `xor a` in `wEnemyMonStatus` clearing. The whole engine is full of such corners. Treat it gently.

---

## Chapter 5 — The atlas

There are 461 maps in Pokémon Prism. Towns, routes, dungeon floors, gym interiors, hidden rooms, every single house you can walk into, every single ship deck, every single cave. Each is its own file in the `maps/` directory.

A map file is, in shape, a small data structure followed by a script — or rather, by a set of small scripts. Let me show you the rough skeleton:

```asm
MapName_MapScriptHeader:
    db <trigger_count>
    db <callback_count>
    dbw TRIGGER_AUTO, .Trigger0
    dbw CB2_OVERWORLD, .Callback

.Trigger0:
    ; script bytecode
    end

.Callback:
    end

MapName_ObjectScripts:
.NPC1Text:
    text "Hello!"
    done

MapName_MapEventHeader::
    db 0, 0

.Warps
    db <warp_count>
    warp_def y, x, dest_index, DESTINATION_MAP

.CoordEvents
    db <coord_count>
    coord_event y, x, script_flag, script_ptr

.BGEvents
    db <bg_count>
    signpost y, x, SIGNPOST_TYPE, text_or_script_ptr

.ObjectEvents
    db <object_count>
    person_event SPRITE_ID, y, x, MOVEMENT, PALETTE, TYPE, TEXT, FUNCTION, FLAG
```

Reading that block from top to bottom: at the start, the map declares its own *triggers* (scripts that run on certain conditions, like the map loading) and *callbacks* (scripts that run every frame). Then come the NPC texts and any per-NPC scripts. Then comes the *event header*, which is a structured table of every interactive thing in the map: warps (the portals between maps), coord events (scripts that fire when you step on a specific tile), background events (signs, hidden items), and object events (NPCs and items you can see).

The *block data* — the actual visual layout of the map, the tiles you walk on — does not live in the `.asm` file. It lives in a separate `.blk` file in one of the map data banks (`$20` through `$35`). The `.asm` file declares the map's *behaviour*; the `.blk` file declares its *appearance*. This separation is one of the reasons the codebase is as navigable as it is — you can change a map's NPCs without touching its tiles.

The scripts, when you write them, look like a small domain-specific language. Here is what a typical NPC interaction reads like:

```asm
.Mom:
    opentext
    writetext .MomText
    waittext
    yesorno
    iffalse .NoThanks
    writetext .MomGiveYouAPokemon
    waittext
    givemon SPECIES_PIKACHU, 5
    setevent EVENT_GOT_PIKACHU_FROM_MOM
    closetext
    end

.NoThanks:
    writetext .NoThanksText
    closetext
    end
```

This is bytecode, not a real language — each line compiles down to a one-byte opcode followed by zero or more operand bytes. But the macros (`opentext`, `writetext`, `iffalse`, `givemon`, `setevent`) are designed to *read* like a language. The interpreter that runs this bytecode is back in `home/scripting.asm`, and the command implementations are in `engine/scripting.asm`. Together they implement a small Forth-like virtual machine, in which a map is a program and the game's state is the heap.

There is a real-world fact about Pokémon games that this architecture explains: why your saved progress in a town is so persistent and so granular. Every NPC, every item ball, every flower-girl waiting to give you a Berry, every gym trainer you've already beaten — each is associated with an *event flag*, a single bit in a large bitfield called `wEventFlags`. When the script fires `setevent EVENT_DEFEATED_GYM_LEADER_FALKNER`, it permanently flips one bit. The NPC's `person_event` line has that flag as its last argument; if the flag is set, the NPC isn't drawn. There are something like 1,500 of these bits in Prism, and they together form the entire long-term state of your playthrough. Save your game and the bitfield goes to SRAM. Load it, and your town springs back exactly as you left it.

I mentioned warps as portals. They are: a `warp_def` says "when the player walks onto tile (y, x), teleport them to warp number N of map DEST." The destination map's warp list contains the actual landing coordinate. So warps are pairs: you say *go to warp 3 of Goldenrod City*, and the engine looks up Goldenrod City's third warp_def, finds its (y, x), and drops you there. That symmetry is part of why connections between rooms feel coherent — every door you walk through has a known landing pad on the other side.

Coord events are similar but more dynamic. They are scripts that fire when the player walks onto a specific tile. The classic example is the rival's first appearance: in vanilla Crystal, you take three steps north of New Bark Town and the rival comes running out at you. That's a coord event, paired with a check that the relevant event flag is *not* yet set (so it doesn't fire a second time after you've already met him).

The town map screen, which you reach through `engine/town_map.asm`, is a separate but related system. It uses *landmarks*, defined in `data/landmarks/`, to map locations onto the larger overworld picture. Every time you walk into a new area, a landmark name is computed and shown in a small banner. The landmark data is essentially a lookup from map ID to a coordinate on the town-map image.

The combined effect — maps as data files with embedded scripts, warps as paired entries, events as bitfield flags, landmarks as lookup tables — is that the entire world of the game is, conceptually, one large database. You can read it almost like a relational schema. Pokémon Prism's 461 maps are 461 rows in a table that knows how to spawn itself when you step into it.

---

## Chapter 6 — The almanac

If the maps are the rooms of the city, the `data/` folder is the almanac that describes the *contents* of the world: every species of Pokémon, every move, every item, every wild encounter table, every Pokédex entry.

The most beautiful single file in `data/` is, in my view, any one of the entries in `data/base_stats/`. Each species — Bulbasaur, Pikachu, Mewtwo, every one — has its own file, and the format is so legible you can almost edit it without reading documentation:

```asm
db PIKACHU
db 35, 55, 40, 50, 50, 90        ; HP, Atk, Def, SpA, SpD, Spe
db ELECTRIC, ELECTRIC            ; type1, type2
db 190                           ; catch rate
db 112                           ; base experience yield
db ITEM_LIGHT_BALL, ITEM_NONE    ; held items (common, rare)
db 127, 0, 10                    ; gender ratio, unused, egg cycles
INCLUDE "gfx/pics/pikachu/dimensions.asm"
db ABILITY_STATIC, ABILITY_LIGHTNING_ROD
db GROWTH_MEDIUM_FAST
dn EGG_FIELD, EGG_FAIRY          ; egg groups, packed in nibbles
```

You can read that and know exactly what Pikachu is, in numbers. Its stats are six bytes. Its types are two bytes. Its catch rate is one byte. Its egg groups are *half a byte each*, packed together via the `dn` ("data nibble") macro into one shared byte. There is no waste here. The original Crystal designers fought for every byte; the Prism developers, inheriting the format, fight for every byte too.

The companion file is `data/evos_attacks.asm`, which holds, for each species, two pieces of information: what level-up moves it learns, and what evolutions (if any) it can undergo. The format is, again, deliberately terse:

```asm
PikachuEvosAttacks:
    db 0,  MOVE_THUNDERSHOCK
    db 0,  MOVE_GROWL
    db 6,  MOVE_TAIL_WHIP
    db 8,  MOVE_THUNDER_WAVE
    db 0, 0
    db EVO_ITEM, ITEM_THUNDER_STONE, RAICHU
    db 0
```

The first block is the level-up moveset: at level 0 (i.e., as a starting move) Pikachu has Thundershock and Growl; at level 6 it learns Tail Whip; at 8 it learns Thunder Wave; and so on, terminated by a `0, 0` marker. The second block is its evolution methods: with a Thunder Stone, Pikachu becomes Raichu, terminated by a single `0`.

Every species in the game has a record like this. There are 260+ species in Prism, so the file is long, but it is also remarkably uniform — the same five-or-so evolution methods, repeated; the same move-level pairs, repeated. You can almost write a script in your head that would generate this from a spreadsheet.

Other corners of `data/`:

- `data/movesets/` — TM/HM compatibility tables (which species can learn which TMs).
- `data/wild/` — wild encounter tables, one file per area. Each table has 10 grass slots, 5 surf slots, and a few special hooks for special areas. Reading a wild table is a small joy: it tells you exactly what you might bump into on Route 32 between dawn and dusk.
- `data/pokedex/` — Pokédex entry text, with the species name, height, weight, and the multi-line description that scrolls when you open the Dex.
- `data/landmarks/` — the table that maps map IDs to overworld landmarks.
- `data/map_objects.asm` — the master table that defines all the NPC sprites: their default palettes, their sprite-sheet identifiers.
- `data/pokemon_names.asm` — the 11-character species name strings. (Yes, 11. POKEMON names in the GB era were 10 characters plus a terminator.)
- `data/sprite_headers.asm` — overworld sprite dimensions and frame counts.
- `data/predefs.asm` — the function-pointer table for the `predef` system, the cross-bank function dispatcher.

There is one more file I want to highlight here, even though it lives in `items/` rather than `data/`: `items/item_attributes.asm`. It is the single source of truth for every item in the game — what it costs, what pocket of the bag it goes into, what it does when used. Every Master Ball, every Repel, every Berry, every Mail item — each gets one row. The format is again terse and verbal:

```asm
ItemAttributes_MasterBall:
    db ITEM_MASTER_BALL
    dw 0                ; price (0 = not sold)
    db HELD_EFFECT_NONE
    db 0
    db ITEMMENU_NOUSE
    db 0
    db POCKETTYPE_BALL
    db 1                ; flags
```

If you have ever wondered what makes Master Ball a Master Ball — `POCKETTYPE_BALL` puts it in the ball pocket; `dw 0` says it's not for sale anywhere; the flag bit says it's a key item; and the actual capture rate that overrides the catch-rate formula lives elsewhere, in the ball-throwing code. But the *metadata* — its identity in the bag — is here.

You can read the data folder like a reference book. It is the only part of the codebase where you can sit down with a coffee and read straight through and learn something concrete. The engine teaches you how the game *works*; the data teaches you what the game *is*.

---

## Chapter 7 — The grammar of the world

In assembly, you do not have variables or functions in the high-level sense. You have *labels* — names for addresses. The assembler turns `MyFunction` into a specific byte offset in the ROM, and from then on every reference to `MyFunction` in the code is, mechanically, a reference to that offset.

But the codebase still needs *symbolic* identifiers for things like move IDs, species IDs, item IDs, map IDs, and so on. There are thousands of them. Every constant has to be assigned a number, and every number has to be unique within its category. Doing that by hand would be miserable. So the codebase has, in `constants/`, an enum system built out of assembler macros.

The two key macros are `const` and `enum`, both defined in `macros/enum.asm`. They are simple in the way that all good 8-bit hacks are simple — once you see them you wonder how you ever lived without them.

```asm
const_def                     ; reset the counter to 0
const HEATH_VILLAGE           ; HEATH_VILLAGE = 0
const ROUTE_69                ; ROUTE_69 = 1
const ROUTE_70                ; ROUTE_70 = 2
```

That's it. The `const_def` macro resets a hidden assembler variable to zero; each `const FOO` defines `FOO` equal to the current value of that variable, then increments it. The result is a sequentially-numbered enumeration with human-readable names.

Now multiply this idea over every category in the game. There is a `const_def` for species IDs, beginning a list of 260+ `const SPECIES_*` definitions. There is another for moves. Another for items. Another for trainer classes. Another for map IDs. Another for event flags. Each list lives in its own file under `constants/`, with the file name describing the category.

The category prefixes are conventions, but they are *strong* conventions:

| Prefix | Lives in | What it identifies |
|--------|----------|---------------------|
| `SPECIES_` | `pokemon_constants.asm` | A Pokémon species |
| `MOVE_` | `move_constants.asm` | A move |
| `ITEM_` | `item_constants.asm` | An item |
| `TRAINER_` | `trainer_constants.asm` | A trainer class |
| `MAP_` | `map_constants.asm` | A map |
| `EVENT_` | `event_flags.asm` | An event flag bit |
| `MUSIC_` | `music_constants.asm` | A song |
| `SFX_` | `sfx_constants.asm` | A sound effect |
| `CRY_` | `cry_constants.asm` | A Pokémon cry |
| `ABILITY_` | `ability_constants.asm` | An ability |
| `SPRITE_` | `sprite_constants.asm` | An overworld sprite |
| `PAL_` | `gfx_constants.asm` | A palette index |

Reading a piece of Prism code, you can usually guess where a constant is defined just from its prefix. This is, quietly, one of the codebase's most important affordances. It is the difference between feeling lost and feeling oriented.

A second important detail of the constants system is that *they are all included into every file*. Every `.asm` file in the codebase begins with `INCLUDE "includes.asm"`, which itself includes `constants.asm`, which itself includes all 38 files under `constants/`. So every symbol defined anywhere in `constants/` is visible everywhere. There is no "import" overhead; the namespaces are flat. This works because the assembler is fast and the codebase is, by the standards of modern projects, not enormous.

The third piece of the grammar is `macros/`. These are not constants but *code-generation macros* — assembler-level functions that expand into longer sequences of bytes. They make the source code denser and more readable. A few of the most-used:

- **`farcall`** and **`predef`** — already mentioned, the cross-bank call macros.
- **`warp_def`**, **`person_event`**, **`signpost`**, **`coord_event`** — the map data macros, which compile into the binary layout of a map's event header.
- **`text`**, **`line`**, **`cont`**, **`para`**, **`done`** — the dialogue text macros, which compile into the bytecode the text engine interprets.
- **`step_left`**, **`step_right`**, **`turn_head`**, **`end_movement`** — the NPC movement script macros.
- **`RGB`** — a three-argument macro for packing a GBC color into the 5-5-5 bit format the hardware expects.
- **`dba`** — pack a far-pointer as three bytes: BANK(addr), LOW(addr), HIGH(addr).
- **`dn`** — pack two 4-bit nibbles into one byte.

The last one — `dn` — is a tiny piece of code that, more than any other, expresses the spirit of this codebase. A nibble is half a byte. If you can fit two values in one byte instead of two, you save a byte. The `dn` macro does exactly that, and it is used everywhere bytes are scarce — egg groups, DVs (the old name for IVs), packed flags. Every byte counts.

Constants and macros are the glue that hold the whole game together. They are not interesting in themselves — nobody reads `pokemon_constants.asm` for fun — but they are what makes the rest of the codebase legible. When you read `givemon SPECIES_PIKACHU, 5`, what you are looking at is the result of a small mountain of bookkeeping that the assembler does for you, every build. The mountain is, mostly, invisible. The fact that it is invisible is the whole point.

---

## Chapter 8 — Where state lives

So far we've talked mostly about code and data — about ROM. But ROM is read-only. The game also needs to *change* things: the player's coordinates, the party Pokémon's HP, the bag's item counts, the time of day. That state lives in RAM, and RAM, on the Game Boy Color, comes in several different flavours.

There are four kinds, each at a fixed address range:

- **VRAM**, `$8000–$9fff`. Video RAM: tile graphics, tilemaps, background data. The CPU writes to it; the LCD reads from it; what's drawn on the screen is, exactly, what is in VRAM at the moment the LCD scans each line.
- **WRAM**, `$c000–$dfff`. Work RAM: the game's general scratchpad. Everything that changes during play and doesn't need to be saved lives here.
- **HRAM**, `$ff80–$fffe`. High RAM: a tiny 127-byte region reserved for the fastest access. The stack lives at the top, scratch variables and interrupt-safe shadows of bank registers live below.
- **SRAM**, `$a000–$bfff`. Save RAM: backed by the cartridge battery, this is where the game writes its save file. When the player turns off the Game Boy, WRAM goes to zero; SRAM, kept alive by a coin-cell battery, persists.

WRAM is the most interesting because it's the largest and most varied. The file `wram.asm` declares every named variable in WRAM — there are hundreds of them — and assigns them to fixed addresses. The build will fail if two variables claim the same address, so the layout is mechanically consistent.

A small tour of the highlights:

- `wPlayerName`, `wRivalName` — the eleven-byte name strings the player and their rival are assigned at the start of the game.
- `wPlayerID` — the two-byte trainer ID. This is the famous "ID number" you see on your trainer card.
- `wPlayerMoney` — three bytes of binary-coded decimal, holding the player's cash. BCD is used because the game frequently has to render money to the screen, and BCD makes that conversion trivial.
- `wPlayerCoins` — Game Corner coins, two bytes.
- `wMap`, `wMapGroup` — the current map's identity.
- `wXCoord`, `wYCoord` — the player's tile coordinates on the current map.
- `wPlayerDirection` — which way the player is facing.
- `wWalkCounter` — a counter that's incremented on every step, used (with the RNG) to decide when wild encounters trigger.
- `wTimeOfDay` — the current time-of-day slot: MORN, DAY, or NITE. This is recomputed from the RTC every few seconds.

A separate section holds the party:

- `wPartyCount` — number of Pokémon in the party, 0 through 6.
- `wPartySpecies` — a seven-byte array of species IDs (six members plus a `$ff` terminator).
- `wPartyMons` — the actual Pokémon structs. Each is 48 bytes, holding the species, moves, stats, EVs, DVs, status, HP, and so on. Six of them, so 288 bytes total.
- `wPartyMonOT` and `wPartyMonNicks` — the original-trainer names and the nicknames for each party member.

The bag is its own world:

- `wNumItems`, `wItems` — the item pocket. `wItems` is a list of (ID, quantity) pairs.
- `wNumBalls`, `wBalls` — the ball pocket.
- `wNumKeyItems`, `wKeyItems` — key items.
- `wTMsHMs` — TM/HM possession, as a bitfield.

And then there's the battle state, which is enormous when a battle is active and ignored otherwise. `wBattleMode` tells you what kind of battle is going on (0 = none, 1 = wild, 2 = trainer). `wBattleMon` and `wEnemyMon` are local copies of the active Pokémon on each side. `wCurMoveNum`, `wCurMove`, `wDamage`, `wTurn` — every variable the battle engine needs is here, in named, fixed slots.

When you save the game, the save routine (`engine/save.asm`) takes a snapshot of the relevant WRAM regions and copies them to SRAM, prefixed with a checksum. There are actually two save slots in SRAM — the save system writes alternately to one and then the other, so that if the cartridge loses power mid-write, the previous save is still intact. On load, both slots are read, both checksums are verified, and the most-recent-valid one is loaded. It is a small but elegant transactional database, implemented in 8-bit assembly.

HRAM is more specialized. It is only 127 bytes. The Game Boy CPU has a special, single-byte instruction (`ldh`) that addresses HRAM specifically, which makes reads and writes to it about half as expensive as reads and writes to WRAM. So HRAM holds the things that are accessed most frequently or that are needed during interrupts:

- `hROMBank` — a shadow of the currently mapped ROM bank, so that interrupts can restore it.
- `hVBlankCounter` — incremented every vertical blank, used for time-based decisions.
- `hDMATransfer` — actually a tiny routine that gets copied to HRAM at boot, because the OAM DMA has a hardware constraint that the CPU must not access the cartridge during the transfer; running the DMA wait loop from HRAM is the standard workaround.
- The stack itself lives in HRAM, descending from `$fffe`.

VRAM, finally, is the screen. The Game Boy Color renders graphics by composing tiles — 8×8 blocks of pixels — from a tile data area into a 32×32 tilemap. Sprites are stored in the OAM (Object Attribute Memory), a separate region at `$fe00`, with 40 slots. Each frame, the LCD scans line by line; what it draws is whatever is in VRAM at that moment. Changing what's on the screen means writing to VRAM, but you can only safely write during the vertical blank interval (about 1.1 milliseconds out of every 16.7), so VRAM updates are batched and queued. The `home/vblank.asm` interrupt handler is what executes the batched updates each frame.

The four kinds of RAM together form the live state of the game. Everything that changes is in one of them. Everything that persists across reboots is in SRAM. Everything that draws to the screen is in VRAM. Everything that's accessed in tight loops is in HRAM. Everything else is in WRAM.

There is, in this neat separation, a quiet expression of one of the deeper truths of game development: a game is, in the end, a function from state to a series of frames. ROM is the function. RAM is the state.

---

## Chapter 9 — The forge

To turn the source code into a running ROM, the build system goes through a long sequence of small, careful steps. The Makefile orchestrates it, but there are several supporting players.

Step one: the C utilities. In `utils/`, the Makefile compiles a small collection of build-time helper programs. `scaninc` is a dependency-tracker that reads `INCLUDE` directives so the build knows which files need recompiling when. `pokepic` is a converter from PNG sprite sheets to the Game Boy's 2-bit-per-pixel tile format. `lzcomp` is the LZ compressor used for graphics. `pngtrim` strips transparent rows from PNGs. `bankends` reads the linker map after a build and reports free space per bank. `ipspatch` and `bspcomp` build distribution patches. `rendergifs` can render the game's maps as animated GIF previews.

Step two: graphics. Every PNG in `gfx/` is converted to the Game Boy's tile format. For Pokémon sprite sheets, the conversion is handled by `utils/pokepic`, which also extracts palette and frame-timing data. For battle backgrounds and other general graphics, a Python script called `gfx.py` does the conversion. For tilesets, the standard `rgbgfx` tool from the RGBDS toolchain is used.

After the raw 2bpp data is produced, it is LZ-compressed by `utils/lzcomp` into a `.lz` file. The runtime decompressor `home/decompress.asm` will undo the compression when the graphics are needed.

Step three: audio. The `audio/ded/` directory contains the Pokémon cry waveforms as `.wav` files. A Python script called `dedenc.py` runs each waveform through a custom compression pipeline: resample to a target rate, encode the deltas at 4 bits per sample, build a Huffman tree over the delta values, emit Huffman-coded bytecode. The output `.ded` files are what the runtime decoder in `home/ded.asm` plays back. DED is a custom codec invented specifically for this game; it lets each cry fit in a few hundred bytes.

Step four: assemble. Six translation units are assembled with `rgbasm`:

- `audio_nodebug.o` from `audio.asm`
- `gfx_nodebug.o` from `gfx.asm`
- `main_nodebug.o` from `main.asm`
- `maps_nodebug.o` from `maps.asm`
- `text_nodebug.o` from `text.asm`
- `wram_nodebug.o` from `wram.asm`

Each top-level `.asm` is a master file that `INCLUDE`s the actual content. `main.asm` is the largest — it pulls in `home/` and every `engine/`, `battle/`, and `event/` file. `maps.asm` includes every map. `audio.asm` includes the music. The split into six units mirrors the categories of the city we toured.

Step five: link. The linker, `rgblink`, takes the six object files and combines them according to `contents/contents.link`, which references `homebank.link`, `romx.link`, `wram.link`, `sram.link`, and `gbs.link`. Sections are assigned to specific banks (the linker scripts decide which) and the binary ROM is produced.

Step six: fix the header. The Game Boy cartridge format requires a small header at `$0100`: title, manufacturer code, CGB flag, licensee, cartridge type (which mapper, which RAM size, which battery), ROM size, header checksum, global checksum. The `rgbfix` tool writes this header into the linked binary, computing the checksums. The result is `pokeprism_nodebug.gbc`, a fully-formed ROM that any Game Boy Color (or emulator) can boot.

Three details worth noting:

First, the build is sensitive to the version of RGBDS. The codebase is locked to RGBDS 0.7.0 specifically. Newer versions removed support for the old-style symbol-assignment syntax that this codebase uses heavily. RGBDS 1.0 fails outright. RGBDS 0.8 produces a thicket of cryptic errors. The fix, both documented in `docs/build.md` and conventional in the Pokémon disassembly community, is to build RGBDS 0.7.0 from source and pin to it. On a fresh macOS install, the procedure takes about ten minutes if everything goes smoothly.

Second, the build produces two ROMs from the same source: `pokeprism_nodebug.gbc` (release) and `pokeprism.gbc` (debug). The difference is a single command-line flag, `-DDEBUG_MODE`, passed to `rgbasm` during the debug assembly. The flag enables a vast set of conditionally-compiled debug features, including in-game debug menus, an emulator-detection routine, extra crash diagnostics, and various developer warps. We'll see those in the next chapter.

Third, the freespace report. After `make all`, you can run `make freespace` to produce `bank_ends.txt`, a list of how many free bytes remain in each ROM bank. The build will not fail just because a bank is nearly full, but if you're adding new content (a new map, a new song, a new move animation), you have to think about which bank it should live in and whether that bank has room. The freespace report is the inventory clerk of the city.

There is a kind of pleasure in a clean build. You see the dependency tracker run, the PNGs get squeezed into LZ-compressed binaries, the assembler chew through tens of thousands of lines of code, the linker fit it all into the cartridge's 128 banks, the header get sealed, and at the end you hold a `.gbc` file in your hand — well, on disk — and you load it into an emulator and the title screen appears. The whole chain, from one source tree to one cartridge, takes about thirty seconds on a modern machine. It is the same chain Nintendo engineers were running in 1999, only their machines were slower and their snacks were better.

---

## Chapter 10 — The back door

There are two ways to alter Pokémon Prism. One is to change the source code and rebuild. The other is to modify a finished cartridge. The codebase contains affordances for both.

The first, source-code path, is what we've spent most of this document on. You change a file, you run `make nodebug`, you get a new ROM. If you want a more powerful development experience — the ability to step through what the game is doing, set breakpoints, watch variables, edit memory live — you use the debug ROM, which is built with `make prism` (an alias for `make pokeprism.gbc`). The debug ROM has, baked into it, two distinct debug menus.

The first is a small **main-menu debug** screen, accessible from the title screen. It is a recovery tool: it can reset the real-time clock, erase the save data, or fix the build-number stored in the save (which is how the game decides whether a save is compatible with the current ROM). These are coarse, save-level operations; they exist so a developer can recover from a save that's gone wrong.

The second is the much larger **in-game debug menu**, accessible from the Start menu while you're in the overworld. It is a tree of submenus:

- **Get #mon** — spawn any species at any level, with an optional held item. There's an Egg variant for testing breeding.
- **Manage Items** — add any item or TM/HM to the bag.
- **Manage Money** — edit the trainer ID, money amount, and coin count.
- **Warp Anywhere** — pick any map by ID and teleport to it.
- **Edit flags** — toggle engine flags (like fly points) and event flags (like story-progression bits).
- **Memory Access** — read or write arbitrary WRAM addresses. Or jump to (execute) an arbitrary ROM address. This is the developer's "god mode".
- **Miscellaneous** — multiplication/division test, sound test, stopwatch test, EXP-group test, credits roll trigger.
- **Pics** — preview every trainer-class sprite and every Pokémon species sprite.

The menu DSL is defined in `macros/debug_menu.asm`. Each menu is a small data declaration; each option points to an action function. Adding a new debug option is cheap, which is the whole point — debug menus are most useful when they're easy to extend, because new ones are added all the time during development.

The conditional compilation pattern is worth understanding. The codebase uses an `IF DEF(DEBUG_MODE) ... ENDC` block to gate large debug-only sections. For places where the *position* of the code must be the same between debug and release builds (so that addresses don't shift), there is a smaller, one-byte macro called `debug_mode_flag`:

```asm
MACRO debug_mode_flag
    if DEF(DEBUG_MODE)
        scf       ; set carry → "debug is on"
    else
        and a     ; clear carry → "debug is off"
    endc
ENDM
```

Both branches emit exactly one byte, so the addresses of everything after it are identical between builds. Callers test the carry flag and branch accordingly. This pattern lets debug-only behavior coexist with release builds without ever shifting any address — which matters because shifted addresses break references in `.sym` files, save files, and external tools.

The second path to altering the cartridge is the `/patch/` directory, which is a completely separate subsystem and one of the most fascinating corners of this project. Here is what it does.

There exists a vanilla copy of Pokémon Crystal 1.1, with a specific SHA-1 hash. If you have that ROM as `baserom.gbc` in the project root, the `make patch` target will not produce a new ROM — instead, it produces a `pokeprism.bsp` file. That `.bsp` is a binary patch in the bspcomp format. Applied to vanilla Crystal, it transforms the Crystal ROM into the Pokémon Prism ROM. So Prism is, in this sense, distributable as a patch, with the original ROM remaining the user's responsibility to provide.

But the patch system does more than just *transform Crystal into Prism*. Many of the `.txt` files in `/patch/` are actually save-file migrations. When a player who has been playing Prism for a year loads up the latest version, their existing save file was written by an older version of the game and may have a slightly different memory layout. The patcher includes a sequence of in-place fix-ups that run on the SRAM image to bring it up to date — repairing party data, resetting RTC state, applying small corrections to items or events.

The fact that save migrations are written in the same DSL as the ROM patch itself is, when you sit with it, a small triumph of engineering elegance. The patcher is, in essence, a tiny scripting language for transforming binary blobs, and the developers reused it for both kinds of binary blob they had to transform.

The key files in `/patch/`:

- `patch.txt` — the entry point.
- `main.txt` — the top-level patching logic.
- `detection.txt`, `version_selections.txt` — figure out which version the user is on.
- `savefile.txt`, `save_patches.txt`, `save_patch_list.txt`, `save_patch_utils.txt`, `apply_party_patches.txt` — the save-migration framework.
- `pokemon_functions.txt`, `item_functions.txt`, `experience.txt` — utility functions for Pokémon mutations.
- `crystal.ips` — the binary IPS diff against vanilla Crystal, used as a reference baseline.

There is also, charmingly, a `lol.txt` and a `lol.ips`. They are an easter egg. I will not spoil it.

The debug menu and the patch system together form the developer-facing infrastructure of the project. The debug menu makes the running game interactively malleable. The patch system makes the *finished* game retroactively malleable, both to alter the cartridge and to migrate existing saves. Together they give the Prism developers a kind of time-travel: they can change the past (via patches) and the present (via debug menus), all while never breaking what the players in the wild have already built.

---

## Epilogue — Reading the ROM like a book

We have walked through ten chapters of a small, dense, beautifully laid-out city. There are a few things I want to leave you with.

The first is the **shape of the codebase**. If you remember nothing else, remember this: the code lives in `home/` and `engine/` and `battle/` and `event/`. The data lives in `data/` and `items/` and `trainers/` and `maps/`. The infrastructure lives in `constants/` and `macros/` and `utils/` and `contents/`. There is a `tools/` folder full of off-ROM helpers in a separate repo, and a `docs/` folder (the one this file is in) full of references. The ROM is built from `main.asm`, with `maps.asm` and the other top-level masters pulled in for separate translation units.

The second is the **shape of the system**. The Game Boy is a 64 KB machine. The cartridge is a 2 MB box that exposes 16 KB slices into that 64 KB space. The game's job is to choose, frame by frame, which slice is mapped in, and to keep its state coherent across those swaps. Every function call across a bank boundary goes through `farcall` or `predef`. Every piece of code in `home/` is callable from any context. Every piece of code in `engine/`, `battle/`, or `event/` lives in a specific bank and is called by name.

The third is the **shape of the state**. Every variable the game uses, while it's running, is in WRAM, HRAM, VRAM, or SRAM. Every name in WRAM has a fixed address, declared in `wram.asm`. The save file is a checksummed dump of the relevant WRAM regions. Loading a save restores those regions, and the game resumes exactly where it left off — because the *state* is exactly that set of bytes.

The fourth is the **shape of the data**. The base stats of every Pokémon, the moves they learn, the wild encounter tables, the trainer parties, the item attributes, the map block data, the dialogue text — all of it lives in `data/` (or the closely-related `items/`, `trainers/`, and `maps/`) in formats that are deliberately legible. You can read these files without running the game and learn most of what the game knows about itself.

The fifth, and most important, is the **shape of the change**. Almost any modification you might want to make to Pokémon Prism — adding a Pokémon, adding a move, adding a map, changing a stat, modifying a dialogue — touches a small, predictable set of files. The codebase is large but locally readable. You don't need to understand the whole thing to make a piece of it bend.

There is a slightly philosophical note I want to end on. Disassemblies and ROM hacks like this one are, in a sense, archaeology turned forward. They take an old artifact — a commercial game that was sold for a season and then forgotten — and they unearth its structure, document its choices, and then *keep going*. They take the original developers' ideas and extend them, twenty years late, in directions those developers never imagined. Pokémon Prism's region was not on the road map at Game Freak. Its abilities, backported from the Game Boy Advance era to the Game Boy Color, did not exist when the cartridge format did. The game runs on hardware it was never designed for and tells stories its original engineers never wrote — but it does so by perfectly respecting the format they did create, by living happily inside every constraint they did set.

That is, I think, the part that makes ROM hacks magical, and that is the part I hope you remember.

Sleep well.

— end —

*If you'd like to go deeper after this, the other documents in this folder cover individual topics in detail: `overview.md` is the project-at-a-glance, `codebase-map.md` is the per-directory file index, `maps-and-events.md` is the scripting reference, `data-formats.md` is the struct layouts, `memory-layout.md` is the WRAM/HRAM/SRAM/VRAM map, `macros-and-constants.md` is the enum and macro reference, `build.md` is the toolchain notes, and `debug-mode.md` is the debug-build and patch-system reference. They are all worth a coffee and an afternoon.*
