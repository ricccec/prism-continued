# Chapter 8 — The Overworld in Motion

Chapters 5, 6 and 7 built the overworld as a *thing*: a map is two header lookups, a block grid, three tileset tables, eight palettes chosen by time of day, a bytecode program that assembles it all, and a script VM that gives it triggers and NPCs. But a map sitting in WRAM is a still photograph. This chapter is about the sixty-times-a-second machine that turns the photograph into a film — the loop that reads the joypad, walks the player one pixel at a time, streams fresh tiles into a video chip with nowhere to put them, ticks every NPC's tiny brain, and, after each completed step, asks a chain of questions: *did you walk onto a warp? into tall grass? into a trainer's line of sight?*

If Chapter 7 was the world's *rules*, this is the world's *clock*.

---

## 8.1 The Question This Chapter Answers

Hold two numbers in your head.

A Prism map is large — a typical route is dozens of blocks wide and tall, and each block is 32×32 pixels. The full decompressed map lives in `wOverworldMap` (`wram.asm`), a 1300-byte buffer of block IDs.

The Game Boy Color's background layer is *not* large. The hardware has exactly one background tile map: a 32×32 grid of 8×8 tiles, 256×256 pixels, and the screen shows a 20×18-tile window onto it. There is no second map, no scrolling framebuffer, no room to pre-render the route and slide a camera across it. The whole visible world, plus a one-tile margin, *is* those 32×32 entries — and they must be rewritten as you walk.

So the central trick of the overworld engine is this: **the BG tile map is a torus the size of one screen, and the engine continuously streams the leading edge of new scenery into the trailing edge of the torus while the hardware scroll registers slide the viewport across it.** Everything else in this chapter — steps, encounters, NPCs, warps — hangs off that loop. We start with the loop itself.

---

## 8.2 The Overworld Loop

The beating heart is `OverworldLoop` in `engine/events.asm`. It is a tiny state machine driven by `wMapStatus`:

```asm
; engine/events.asm
OverworldLoop::
	xor a
	ld [wMapStatus], a
.loop
	call .OverworldLoop
	jr nc, .loop
	ret

.OverworldLoop
	ld a, [wMapStatus]
	and a
	jr z, StartMap        ; 0: first-time setup
	dec a
	jr z, EnterMap        ; 1: fade/scroll in
	dec a
	jr z, HandleMap       ; 2: the steady state
	scf
	ret
```

`StartMap` and `EnterMap` run once on arrival (this is the map-setup VM from Chapter 6). `HandleMap` is where the game *lives* — every frame you spend walking around is one pass through it:

```asm
; engine/events.asm
HandleMap:
	call ResetOverworldDelay
	call HandleMapTimeAndJoypad     ; read the joypad, advance the clock
	call HandleCmdQueue             ; run deferred script commands
	call MapEvents                  ; player events + running scripts
	ld a, [wMapStatus]
	cp 2
	jr nz, .done
	call DoBackgroundEvents         ; twice
	call DoBackgroundEvents
.done
	and a
	ret
```

Two things are worth pausing on.

First, `MapEvents` calls `PlayerEvents` — the priority chain that asks all the "what did I just step onto?" questions. We will dissect it in §8.7. It only runs when no script is already executing (`wMapEventStatus`), which is how a cutscene or a menu *freezes* the overworld: while a script owns the VM, player events are gated off.

Second, `DoBackgroundEvents` runs **twice** per `HandleMap`. That is the engine's basic unit of motion:

```asm
; engine/events.asm
DoBackgroundEvents:
	call HandleOverworldObjects     ; advance every object's step one tick
	call UpdateStableRNGSeeds
	call NextOverworldFrame         ; wait for the frame to actually pass
	call HandleMapBackgroundEvents  ; sprites, landmark signs, and the scroll
	jp EnableEventsIfPlayerNotMoving
```

`NextOverworldFrame` is the metronome:

```asm
; engine/events.asm
NextOverworldFrame:
	ld a, [wOverworldDelay]
	and a
	jp nz, DelayFrame
	ld a, $82
	ld [wOverworldDelay], a
	ret
```

If a delay is pending it burns a frame; otherwise it reloads the counter. The effect is a steady cadence that paces movement so the player walks at a constant, hardware-independent speed. And the last call in the chain, `HandleMapBackgroundEvents`, is where the camera actually moves:

```asm
; engine/events.asm
HandleMapBackgroundEvents:
	callba _UpdateSprites
	callba RunLandmarkSignAnim
	jpba ScrollScreen
```

`ScrollScreen` is the bottom of the rabbit hole. To understand it we need the two maps.

---

## 8.3 The Two Maps in Memory

The engine keeps the world in two completely different representations, and the magic of smooth scrolling is the bridge between them.

| | `wOverworldMap` | The VRAM BG tile map |
|---|---|---|
| **What it holds** | Block IDs (one byte per 32×32-pixel block) | Tile IDs (one byte per 8×8-pixel tile) |
| **Size** | 1300 bytes — the whole loaded map plus a 3-block border | 32×32 = 1024 entries — exactly one screen + margin |
| **Where** | WRAM (`wram.asm`) | Video RAM, written only during VBlank |
| **Role** | The "truth" — what the map *is* | The "view" — what the hardware draws right now |

Two pointers tie them together, both in `wram.asm`:

- `wOverworldMapAnchor` — where in `wOverworldMap` the top-left of the visible area currently sits.
- `wBGMapAnchor` — where in the 32×32 VRAM torus the top-left tile currently sits. Its low 5 bits are a column (0–31), the next 5 bits a row (0–31); as you walk, this pointer *wraps* around the torus rather than the map ever being recentred.

Between the block buffer and the tile map sits one more staging area — the shadow buffers `wTileMap` (the 20×18 visible tile grid in WRAM) and `wAttrMap` (its per-tile palette/attribute twin). Code never pokes VRAM directly during active rendering; it writes here and to small queues, and VBlank does the copy. Which brings us to the trick itself.

---

## 8.4 Smooth Scrolling: The Tile Map as a Torus

A single step covers one block — 16 pixels — but it does not happen in one frame. It happens as a smear of small offsets over several frames, and two independent things move during that smear:

1. **The viewport slides**, pixel by pixel, via the hardware scroll registers.
2. **One new row or column of tiles is streamed** into the torus so that, by the time the viewport has slid a full block, fresh scenery has appeared at the leading edge.

### The viewport slides

Every frame, `ScrollScreen` (in `engine/player_step.asm`) nudges the shadow scroll registers by the player's current per-frame pixel vector:

```asm
; engine/player_step.asm
ScrollScreen::
	ld a, [wPlayerStepVectorX]
	ld d, a
	ld a, [wPlayerStepVectorY]
	ld e, a
	ldh a, [hSCX]
	add d
	ldh [hSCX], a
	ldh a, [hSCY]
	add e
	ldh [hSCY], a
	ret
```

`hSCX` and `hSCY` (`hram.asm`) are shadow copies; the real hardware registers are written during VBlank, in `VBlank0` (`home/vblank.asm`):

```asm
; home/vblank.asm
	ldh a, [hSCX]
	ldh [rSCX], a
	ldh a, [hSCY]
	ldh [rSCY], a
```

This is why the world glides instead of snapping a block at a time: the BG layer is being scrolled at sub-tile, single-pixel granularity by hardware, for free, every frame.

### One new row/column is streamed

Sliding the viewport alone would scroll you straight off the edge of the 256-pixel torus and back around to stale tiles. So as the anchor advances, the engine rewrites the row or column that is about to come into view. The four scroll routines live in `home/map.asm` — `ScrollMapUp`, `ScrollMapDown`, `ScrollMapLeft`, `ScrollMapRight` — and each calls one of two workhorses, `UpdateBGMapRow` or `UpdateBGMapColumn`. Here is the row version:

```asm
; home/map.asm
UpdateBGMapRow::
	ld hl, wBGMapBufferPtrs
	...
.loop
	ld a, e
	ld [hli], a            ; store target VRAM address (low)
	ld a, d
	ld [hli], a            ; ...and high
	ld a, e
	inc a
	inc a
	and $1f                ; <-- wrap within 32 columns: the torus
	ld b, a
	ld a, e
	and $e0                ; keep the row/bank bits intact
	or b
	ld e, a
	dec c
	jr nz, .loop
	ld a, SCREEN_WIDTH
	ldh [hBGMapTileCount], a
	ret
```

The crucial line is `and $1f`. Column addresses are masked to five bits, so advancing past column 31 lands back on column 0 — the wrap that makes a 32-wide map behave as an endless cylinder. The column version (`UpdateBGMapColumn`) does the same for rows with `res 2, d`, keeping the address inside the two-bank BG-map region.

Note what these routines actually write: not VRAM, but `wBGMapBufferPtrs` — a list of *target addresses*, paired with tile bytes staged in `wBGMapBuffer` and palette bytes in `wBGMapPalBuffer` (all in `wram.asm`). They also set `hBGMapTileCount`. They are building a work order for VBlank.

### VBlank fills it in

`UpdateBGMapBuffer` (`home/video.asm`) is the only code allowed to touch the BG map, and it runs in the narrow VBlank window when VRAM is safe:

```asm
; home/video.asm
UpdateBGMapBuffer::
	ldh a, [hBGMapUpdate]
	and a
	ret z
	...
	ld hl, wBGMapBufferPtrs
	ld sp, hl              ; abuse the stack pointer to pop addresses fast
	...
.next
	pop bc                 ; bc = a queued VRAM address
	ld a, 1
	ldh [rVBK], a          ; bank 1: attributes/palette
	... store pal bytes ...
	xor a
	ldh [rVBK], a          ; bank 0: tile IDs
	... store tile bytes ...
	ldh a, [hBGMapTileCount]
	dec a
	dec a
	ldh [hBGMapTileCount], a
	jr nz, .next
```

`hBGMapUpdate` is the "there is work to do" flag; `hBGMapTileCount` is how much. The routine flips `rVBK` between VRAM bank 0 (tile indices) and bank 1 (the CGB attribute map — palette and priority) for each tile, because in Prism every BG tile carries both. When it is done it clears `hBGMapUpdate` and the torus has a fresh leading edge.

### Putting one step together

So a single northward step looks like this, spread across its frames:

1. The player object begins a step (§8.5); `wPlayerStepVectorY` is set to a few pixels per frame upward.
2. Each frame, `ScrollScreen` subtracts that from `hSCY`; VBlank copies it to `rSCY`; the world slides down by those pixels.
3. As the anchor crosses into a new block row, `UpdateOverworldMap` (`engine/player_step.asm`) advances `wBGMapAnchor`/`wOverworldMapAnchor` and calls `ScrollMapDown`, which queues the new top row via `UpdateBGMapRow`.
4. Next VBlank, `UpdateBGMapBuffer` writes that row into VRAM — wrapped around the torus — and sets `rSCX`/`rSCY`.
5. After 16 pixels the step completes, the player's tile coordinates update, and `PlayerEvents` gets to ask its questions.

The player never moves on the map; the *map* moves under a fixed-centre camera, repainting its own trailing edge as it goes. That is the whole illusion.

---

## 8.5 The Anatomy of a Step

Movement is per-*object*, not just per-player. Every moving thing on the map — the player and up to 15 NPCs — is one entry in a fixed array of object structs.

### The object struct

`object_struct` (`wram.asm`) is 40 bytes. The fields that matter for motion:

| Field | Meaning |
|---|---|
| `Direction` | the direction this step is heading (DOWN/UP/LEFT/RIGHT) |
| `Facing` | the *visual* facing, packed into direction bits |
| `StepType` | which animation state machine drives this object (`STEP_TYPE_NPC_WALK`, `STEP_TYPE_PLAYER_WALK`, …) |
| `StepDuration` | frames remaining in the current step |
| `ObjectStepFrame` | walk-cycle animation frame |
| `SpriteX` / `SpriteY` | on-screen pixel position |
| `StandingMapX` / `StandingMapY` | current tile; `LastMapX/Y` hold the previous tile |

The array is `wPlayer`, then `wMap1` through `wMap15` (`wram.asm`) — `NUM_OBJECTS` = **16** total, the player plus fifteen NPC slots. This is the hard cap on how many sprites a single map can animate at once.

### From one tile to N frames of animation

How does "walk one tile north" become a smooth glide? Through a tiny table of step vectors in `engine/map_objects.asm`:

```asm
; engine/map_objects.asm
StepVectors:
; x,  y, duration, speed
	; slow
	db  0,  1, 32, 1
	...
	; normal
	db  0,  1, 16, 1
	db  0, -1, 16, 1
	db -1,  0, 16, 1
	db  1,  0, 16, 1
	; fast
	db  0,  4,  4, 4
	...
	; running shoes
	db  0,  2,  8, 2
	...
```

Read the "normal" rows: a step moves ±1 pixel per frame for 16 frames — exactly one 16-pixel block. Running shoes move 2 pixels for 8 frames; the fast/jump variant moves 4 pixels for 4 frames. Different speeds, same distance.

Each frame, `AddStepVector` (`engine/map_objects.asm`) accumulates the per-frame delta into the object's pixel position:

```asm
; engine/map_objects.asm
AddStepVector:
	call GetStepVector
	...
	ld hl, OBJECT_SPRITE_X
	add hl, bc
	ld a, [hl]
	add d                  ; += x delta
	ld [hl], a
	ld hl, OBJECT_SPRITE_Y
	add hl, bc
	ld a, [hl]
	add e                  ; += y delta
	ld [hl], a
```

`NPCStep` runs this for NPCs and decrements `StepDuration`; when it hits zero the object's tile coordinates commit and it returns to `STANDING`. `PlayerStep` is the player's variant, and it is special: it also drives the screen scroll vectors that §8.4 consumes. The player's `_HandlePlayerStep` (`engine/player_step.asm`) is the one that calls `UpdateOverworldMap` to advance the anchors at the right moment of the step. NPC sprites move within the visible window; the player's "movement" is really the *world* scrolling — two different code paths producing the same on-screen result.

### Looking before you leap

Before any step commits, the engine checks what is in the way. `GetCoordTile` (`home/map.asm`) reads the collision byte for a tile coordinate by walking the same block→metatile→collision indirection from Chapter 5, and `GetTileCollision` (`home/map_objects.asm`) reduces a tile to its collision class:

```asm
; home/map_objects.asm
GetTileCollision::
	push hl
	ld h, HIGH(TileCollisionTable)
	ld l, a
	ld a, BANK(TileCollisionTable)
	call GetFarByte
	and $f                 ; low nibble = collision class
	pop hl
	ret
```

NPC movement layers richer rules on top of this in `engine/npc_movement.asm` — `IsNextTileWalkable`, `IsNextTileSurfable`, directional-tile checks for one-way river currents, and `WillPersonBumpIntoSomeoneElse` so two NPCs never occupy the same tile.

---

## 8.6 NPCs With a Heartbeat

A map's NPCs are spawned from its object events (Chapter 7) into the 15 NPC slots. What gives each one *behaviour* is its movement type — the `SPRITEMOVEDATA_*` byte from its `person_event`.

The constants live in `constants/sprite_constants.asm`, and there are around forty of them:

```asm
; constants/sprite_constants.asm
	const SPRITEMOVEDATA_WANDER               ; 02
	const SPRITEMOVEDATA_SPINRANDOM_SLOW      ; 03
	const SPRITEMOVEDATA_WALK_UP_DOWN         ; 04
	const SPRITEMOVEDATA_WALK_LEFT_RIGHT      ; 05
	const SPRITEMOVEDATA_STANDING_DOWN        ; 06
	...
	const SPRITEMOVEDATA_PLAYER               ; 0b
	const SPRITEMOVEDATA_FOLLOWING            ; 13
	const SPRITEMOVEDATA_SCRIPTED             ; 14
	...
```

Each maps to a *movement function* (`SPRITEMOVEFN_*`, same file) — `RANDOM_WALK_XY`, `SLOW_RANDOM_SPIN`, `STANDING`, `FOLLOW`, `OBEY_DPAD` (the player's), and so on. `HandleCurNPCStep` (`engine/map_objects.asm`) dispatches on the object's `StepType` each idle tick, and for objects that are merely standing around, `MapObjectMovementPattern` rolls the dice on whether to wander, spin, or pace this cycle. A `WANDER` NPC, given a free frame, picks a random direction, checks it is walkable, and starts a step; a `WALK_LEFT_RIGHT` NPC is pinned to one axis and bounded by its wander radius.

### Facing, and turning to face you

The visual facing direction is two bits, defined in `constants/map_constants.asm`:

```asm
; constants/map_constants.asm
OW_DOWN  EQU DOWN  << 2
OW_UP    EQU UP    << 2
OW_LEFT  EQU LEFT  << 2
OW_RIGHT EQU RIGHT << 2
```

When a script runs `faceplayer`, `Script_faceplayer` (`engine/scripting.asm`) takes the last-talked object, calls `GetRelativeFacing` (`engine/relative_facing.asm`) to compute which way it must turn to point at the player, and writes the result into the object's `Facing`:

```asm
; engine/scripting.asm
Script_faceplayer:
	ldh a, [hLastTalked]
	and a
	ret z
	ld d, 0                ; player is object 0
	ldh a, [hLastTalked]
	ld e, a
	callba GetRelativeFacing
	...
	jp ApplyPersonFacing
```

`GetRelativeFacing` compares the two objects' tile coordinates and picks the axis with the greater separation — the same Manhattan-distance idea the trainer line-of-sight check uses next.

---

## 8.7 Triggers Underfoot

Once a step completes, `PlayerEvents` (`engine/events.asm`) runs its priority chain. Order is everything: the first handler that claims the step wins and the rest are skipped.

```asm
; engine/events.asm  (PlayerEvents, abridged)
	call CheckTrainerBattle3     ; a trainer sees you?
	...
	call CheckTileEvent          ; warp? trigger? wild grass?
	...
	call DoMapTrigger
	call CheckTimeEvents
	call OWPlayerInput           ; otherwise: read the d-pad, start a step
```

Trainers get first refusal (§8.9). If no trainer fires, `CheckTileEvent` runs its own sub-chain — and notice it is gated by individual bits of `wScriptFlags3`, so a script can selectively disable connections, triggers, step-counting or encounters:

```asm
; engine/events.asm  (CheckTileEvent, abridged)
	callba CheckMovingOffEdgeOfMap   ; 1. crossing into a connected map
	jr c, .map_connection
	call CheckWarpTile               ; 2. standing on a warp
	jr c, .warp_tile
	call nz, RunCurrentMapXYTriggers ; 3. a coordinate trigger
	ret c
	call CountStep                   ; 4. step counter (Repel, eggs, …)
	ret c
	call RandomEncounter             ; 5. a wild battle
	ret c
```

### Coordinate events

`RunCurrentMapXYTriggers` (`home/map.asm`) is how stepping onto an exact tile fires a script — the runtime side of the `coord_event` macro. It converts the player's standing coordinates to map space (subtracting the 4-tile border) and scans the map's trigger table for a matching trigger-ID + X + Y. An optional event flag can gate it, so a trigger can be made one-shot. On a hit it jumps straight into `CallScript`.

### Wild encounters

`RandomEncounter` (`engine/events.asm`) is step 5:

```asm
; engine/events.asm
RandomEncounter::
	call CheckWildEncounterCooldown
	jr c, .nope
	call CanUseSweetScent
	jr nc, .nope
	ld hl, wStatusFlags2
	callba TryWildEncounter
	jr nz, .nope
	ld a, BANK(WildBattleScript)
	ld hl, WildBattleScript
	jp CallScript
```

It only matters on encounter terrain, which `CheckGrassCollision` (`engine/tile_events.asm`) defines:

```asm
; engine/tile_events.asm
CheckGrassCollision::
	ld a, [wPlayerStandingTile]
	ld hl, .blocks
	jp IsInSingularArray
.blocks
	db COLL_TALL_GRASS
	db COLL_SUPER_TALL_GRASS
	db COLL_SNOW
	db COLL_WATER
	db -1
```

The roll itself is rate-driven, and the rate is chosen by time of day. When a map loads, `LoadWildMonData` (`engine/wildmons.asm`) copies three bytes — `wMornEncounterRate`, `wDayEncounterRate`, `wNiteEncounterRate` (`wram.asm`) — out of the map's wild table, and `GetMapEncounterRate` picks the right one:

```asm
; engine/wildmons.asm
GetMapEncounterRate:
	ld hl, wMornEncounterRate
	call CheckOnWater
	ld c, 3                 ; water uses a 4th slot
	jr z, .ok
	ld a, [wTimeOfDay]
	ld c, a                 ; else index by morn/day/nite
.ok
	ld b, 0
	add hl, bc
	ld b, [hl]
	ret
```

Repels and lures bias the roll through `wEncounterRateStage` (`wram.asm`), which `LoadWildMonData` initialises to the neutral middle value. (Which *species* you meet, and how the slots are weighted, is the wild-table data from Chapter 4; this chapter is only about *when* a battle fires.)

---

## 8.8 Warps and the Seamless Seam

Chapter 7 covered warps and connections as *data* — the `warp_def` records and the `connection` macro's assemble-time offset math. Here we look at them as *motion*: what the camera and the two map buffers actually do at the moment of transition.

### Warps: tear down and rebuild

A warp is detected by collision class. `CheckWarpCollision` (`engine/tile_events.asm`) matches the warp family of high-nibble collision values; `CheckDirectionalWarp` handles carpet tiles and staircases that only warp if you walk *into* them. When `CheckWarpTile` claims a step, `GetDestinationWarpNumber` (`home/map.asm`) finds which warp entry you are standing on, and `CopyWarpData` resolves the destination:

```asm
; home/map.asm  (CopyWarpData, abridged)
	... read destination warp number ...
	cp $ff
	jr nz, .normal
	; $ff = "return to where you came from"
	ld a, [wBackupWarpNumber]
	...
.normal
	ld [wNextWarp], a
	...
	ld [wNextMapGroup], a
	...
	ld [wNextMapNumber], a
	; and stash the current spot as the next backup
```

That `$ff` convention is how cave exits work without hard-coding a return address: every warp records where you came *from* in `wBackupWarpNumber`, so a door marked `$ff` simply sends you back.

A warp is a *hard* transition. The map-setup path for a door (`MapSetupScript_Door`, `engine/map_setup.asm`) fades the palettes out, and the plain warp path (`MapSetupScript_Warp`) disables the LCD entirely, then `LoadBlockData` decompresses the whole new map, VRAM is reloaded, palettes and objects are loaded, and the screen fades back in. The torus is rebuilt from scratch; there is no continuity to preserve.

### Connections: never let go of the screen

A connection is the opposite. Walking off the edge of a route into the next one must not blink. The trick was set up long before you reached the seam: when the map loaded, `FillMapConnections` (`home/map.asm`) already decompressed three-block-wide strips of every neighbouring map into the border of `wOverworldMap`. You were *already looking at* the first few blocks of the next route.

So crossing the seam does not load a map — it *re-anchors* one. `EnterMapConnection` (`engine/warp_connection.asm`) switches `wMapGroup`/`wMapNumber` to the neighbour, shifts the player's coordinates into the new map's frame, and recomputes `wOverworldMapAnchor` to point at the right spot in the already-filled buffer:

```asm
; engine/warp_connection.asm  (EnterEastConnection, abridged)
	ld a, [wEastConnectedMapGroup]
	ld [wMapGroup], a
	ld a, [wEastConnectedMapNumber]
	ld [wMapNumber], a
	ld a, [wEastConnectionStripXOffset]
	ld [wXCoord], a
	...
	ld a, l
	ld [wOverworldMapAnchor], a   ; just move the camera anchor
```

`MapSetupScript_Connection` (`engine/map_setup.asm`) deliberately omits the LCD-off and the palette fade that the warp path uses. The display stays live; the scroll never stops; only the bookkeeping changes underneath. That asymmetry — warp tears down, connection re-anchors — is the entire difference between a doorway and a route border.

---

## 8.9 Line of Sight: How a Trainer Spots You

This is the one overworld mechanic the earlier chapters never showed, and it is simpler than it looks. After every step, `CheckTrainerBattle` (`home/trainer.asm`) loops over all 15 NPC slots and, for each that is a visible, un-beaten trainer, asks `FacingPlayerDistance` one question: *am I facing the player, and how far away are they?*

```asm
; home/trainer.asm  (FacingPlayerDistance, abridged)
FacingPlayerDistance::
	ld hl, OBJECT_NEXT_MAP_X
	add hl, bc
	ld d, [hl]
	ld hl, OBJECT_NEXT_MAP_Y
	add hl, bc
	ld e, [hl]
	ld a, [wPlayerStandingMapX]
	cp d
	jr z, .CheckY          ; same column → maybe facing up/down
	ld a, [wPlayerStandingMapY]
	cp e
	jr z, .CheckX          ; same row → maybe facing left/right
	and a
	ret                    ; off-axis → cannot be seen
.CheckY:
	... player above or below? does the trainer face that way? ...
.CheckX:
	... player left or right? does the trainer face that way? ...
.CheckFacing:
	call GetSpriteDirection
	cp e
	jr nz, .NotFacing
	scf                    ; carry = "I see them", distance in d
	ret
```

Three facts fall out of this:

- **Sight is orthogonal only.** The player must share the trainer's row or column. There is no diagonal vision.
- **Walls do not block sight.** Nothing here consults the collision map; a trainer "sees" straight through anything on the shared axis. Level designers manage this by placement, not by occlusion.
- **Range is per-trainer.** Back in `CheckTrainerBattle`, the returned distance is compared against the trainer's own `MAPOBJECT_PARAMETER` byte — its sight range — so a trainer can see two tiles or five.

When a trainer claims a step, the engine raises `PLAYEREVENT_SEENBYTRAINER`, which runs `SeenByTrainerScript` (`engine/std_scripts.asm`): pop the `!` bubble (`showemote EMOTE_SHOCK`), then `TrainerWalkToPlayer`, which walks the NPC up the shared axis to stand in front of you (pathing via `engine/walk_follow.asm`) before the battle script fires. Spotted → approach → battle, all from one orthogonal comparison.

---

## 8.10 Pressing A: Interaction

Walking *into* things triggers events; pressing A *at* things triggers interaction. `CheckAPressOW` (`engine/events.asm`) is the dispatcher, and like every overworld decision it is a priority chain:

```asm
; engine/events.asm
CheckAPressOW:
	ldh a, [hJoyPressed]
	and A_BUTTON
	ret z
	call TryObjectEvent       ; 1. an NPC in front of me?
	ret c
	call TryReadSign          ; 2. a signpost?
	ret c
	jp CheckFacingTileEvent   ; 3. a tile event (Cut tree, water…)
```

`TryObjectEvent` calls `CheckFacingObject` (`engine/npc_movement.asm`) to find the object on the tile you face and run its script. If there is no NPC, `TryReadSign` calls `CheckFacingSign` (`home/map.asm`), which scans the map's signpost array for one whose coordinates match the faced tile:

```asm
; home/map.asm  (CheckFacingSign, abridged)
CheckFacingSign::
	call GetFacingTileCoord
	...
.loop
	ld a, [hli]
	cp e                  ; match Y
	jr nz, .next
	ld a, [hli]
	cp d                  ; match X
	jr z, .copysign
.next
	...
.copysign
	ld de, wCurSignpostYCoord
	ld bc, 5
	rst CopyBytes         ; copy the 5-byte signpost into WRAM
	scf
	ret
```

The copied signpost's *type* byte then selects a handler in `TryReadSign`'s jump table (`engine/events.asm`). The types are defined in `constants/map_constants.asm`:

```asm
; constants/map_constants.asm
	const SIGNPOST_READ          ; 0  plain text
	const SIGNPOST_UP            ; 1  only readable facing up
	...
	const SIGNPOST_ITEM          ; 5  a hidden item
	const SIGNPOST_LOAD          ; 6
	const SIGNPOST_TEXT          ; 7
	const SIGNPOST_JUMPSTD       ; 8  call a standard script
	const SIGNPOST_JUMPSTDNOSFX  ; 9
```

### Hidden items

`SIGNPOST_ITEM` is how Prism does hidden items — they are signposts you cannot see. The handler (`engine/events.asm`) checks the item's event flag, and if it is unset, hands off to `HiddenItemScript` (`event/hidden_item.asm`):

```asm
; event/hidden_item.asm
HiddenItemScript::
	opentext
	copybytetovar wCurSignpostItemID
	itemtotext 0, 0
	writetext .found_text
	giveitem ITEM_FROM_MEM
	...
	callasm .set_event      ; set the flag so it never returns
	playwaitsfx SFX_ITEM
	itemnotify
	endtext
```

Setting the flag atomically with the pickup is what stops a found item from reappearing.

---

## 8.11 Field Moves

The HMs reach out of the bag and change the world. They all live in `engine/overworld/field_moves.asm` and they all share one shape: clear a scratch buffer, run a little jump-table state machine, gate on a badge, check the terrain in front of you, and — if everything passes — queue a script that performs the actual transformation. Cut is the clearest example:

```asm
; engine/overworld/field_moves.asm
CutFunction:
	call ClearFieldMoveBuffer
.loop
	ld hl, .Jumptable
	call FieldMoveJumptable
	jr nc, .loop
	...
.CheckAble
	CheckEngine ENGINE_NATUREBADGE    ; right badge?
	jr z, .nohivebadge
	call CheckMapForSomethingToCut    ; a tree in front?
	jr c, .nothingtocut
	ld a, 1
	ret
.DoCut
	ld hl, Script_CutFromMenu
	call QueueScript                  ; let a script do the work
	ld a, $81
	ret
```

### Cut, end to end: how a tree becomes grass

`CheckMapForSomethingToCut` (`engine/overworld/field_moves.asm`) is where "a tree in front?" is actually decided, and it asks **two** independent questions about the block you face. Both must pass:

```asm
; engine/overworld/field_moves.asm  (CheckMapForSomethingToCut, abridged)
	call GetFacingTileCoord
	ld c, a
	callba CheckCutCollision      ; 1. is the faced quadrant a cuttable collision class?
	ccf
	ret c
	call GetBlockLocation         ; hl = address of this block inside wOverworldMap
	ld c, [hl]                    ; c = the block ID sitting there
	ld hl, CutTreeBlockPointers
	call CheckOverworldTileArrays ; 2. is that block ID registered as cuttable in this tileset?
	pop hl
	ccf
	ret c
```

The first question is collision: `CheckCutCollision` (`engine/tile_events.asm`) confirms the faced quadrant is `COLL_CUT_TREE` (or one of the tall-grass classes). Recall from Chapter 5 that the `*_collision.asm` files are indexed **by block ID**, and each `tilecoll` line gives the collision of a block's four quadrants — so making a block cuttable means giving one of its quadrants the `CUT_TREE` class.

The second question is registration. `CutTreeBlockPointers` is a dictionary keyed by tileset; each tileset points at its own little table of **three-byte records**:

```asm
; engine/overworld/field_moves.asm
.kanto	; Kanto OW
	db $82, $0a, $00 ; tree
	db -1
```

The three bytes are **[block to match] · [block to swap in] · [animation index]**. `CheckOverworldTileArrays` walks the current tileset's table (stride 3) looking for the faced block ID; on a hit it returns the second byte (the replacement block) in `b` and the third (the animation) in `c`. `CheckMapForSomethingToCut` then stashes three things in WRAM: the replacement block into `wFieldMoveCutTileReplacement`, the animation into `wWhichCutAnimation`, and — crucially — the *address of the block inside `wOverworldMap`* into `wFieldMoveCutTileLocation`. It has now recorded both *what* to draw and *where*.

The transformation itself is one store. Once the "used CUT!" script has played the cry and animation, `CutDownTreeOrGrass` dereferences that saved address and overwrites the live block:

```asm
; engine/overworld/field_moves.asm  (CutDownTreeOrGrass, abridged)
	ld hl, wFieldMoveCutTileLocation
	ld a, [hli]
	ld h, [hl]
	ld l, a                              ; hl = the tree's cell in wOverworldMap
	ld a, [wFieldMoveCutTileReplacement]
	ld [hl], a                           ; tree block ID → grass block ID
	...
	call GetMovementPermissions          ; recompute what is now walkable
```

Because the block ID in `wOverworldMap` is the single source of truth (§8.3), that one byte-write changes everything downstream: the next scroll repaints the grass tiles, and `GetMovementPermissions` re-reads the new block's collision so you can walk where the trunk used to be. The third byte, meanwhile, chose the flourish — `OWCutAnimation` (`event/field_moves.asm`) reads `wWhichCutAnimation` and plays *split the tree in half* for `$00` or *mow the lawn* (flying leaves) for `$01`, which is why every tree row ends in `$00` and every grass row in `$01`.

The practical upshot for map-making: a cuttable tree needs **both** halves wired, and they live in different files. The block must carry a `CUT_TREE` quadrant in its tileset's `*_collision.asm`, *and* the block ID must be listed in that tileset's table inside `CutTreeBlockPointers`. Set only the collision and Cut's prompt appears but nothing happens after "Yes" (the block lookup fails); list the block without the collision and it fails the first check instead.

The pattern repeats for each move, varying only the badge and the terrain test — `CutFunction`, `SurfFunction`, `FlyFunction`, `StrengthFunction`, `OWFlash`, `HeadbuttFunction`, `RockSmashFunction` (Prism does not implement Waterfall or Whirlpool as separate field moves). Two of them change *persistent state* rather than a single tile:

- **Surf** flips the player into a riding state. `SurfFunction` checks `ENGINE_HAZEBADGE`, confirms the faced tile is water (and not too-fast current), then sets `wPlayerState` to `PLAYER_SURF` (`constants/wram_constants.asm`). That state survives until you step back onto land, and it changes both the player sprite and which collision classes count as walkable.
- **Strength** sets a flag in `wBikeFlags` so boulders stay pushable for the rest of the map.

Flash is a special case worth noting because it ties back to Chapter 6: `OWFlash` only succeeds when the current palette set is the all-dark cave palette, and on success it queues the script that swaps in the lit palette — the field move and the colour system meeting in the middle.

---

## 8.12 The Overworld Menu, Briefly

Pressing START is just another thing `HandleMap` notices. `CheckMenuOW` (`engine/events.asm`) watches the joypad and, on START, calls a script:

```asm
; engine/events.asm
CheckMenuOW:
	...
	bit START_F, a
	jr z, .NoMenu
	ld a, BANK(StartMenuScript)
	ld hl, StartMenuScript
	jp CallScript
```

`StartMenuScript` runs `StartMenu` (`engine/startmenu.asm`) and then dispatches on `hMenuReturn`. The important structural point — and the reason the menu belongs in this chapter at all — is *how it pauses the world*: opening the menu runs a script, and as we saw in §8.2, while a script owns the VM `PlayerEvents` is gated off. The overworld loop keeps spinning (sprites still animate, the clock still ticks), but the player cannot move and no triggers fire until `StartMenu` returns control. The menu's *contents* — the Pokédex, the pack, the party and stats screens, and the rendering that draws them — are the presentation layer, and that is Chapter 10's subject. Here it is enough to see the seam: START is an interaction like any other, and the menu is a script that holds the VM until you close it.

---

## 8.13 Reference: Key Files and Symbols

| Concern | File | Key symbols |
|---|---|---|
| Overworld loop & cadence | `engine/events.asm` | `OverworldLoop`, `HandleMap`, `DoBackgroundEvents`, `NextOverworldFrame`, `wOverworldDelay` |
| Player events priority | `engine/events.asm` | `PlayerEvents`, `CheckTileEvent` |
| Screen scroll | `engine/player_step.asm`, `home/vblank.asm` | `ScrollScreen`, `_HandlePlayerStep`, `UpdateOverworldMap`, `hSCX`/`hSCY`→`rSCX`/`rSCY` |
| Tile streaming | `home/map.asm`, `home/video.asm` | `ScrollMap{Up,Down,Left,Right}`, `UpdateBGMapRow`/`Column`, `UpdateBGMapBuffer`, `wBGMapBuffer(Ptrs)`, `hBGMapUpdate`/`hBGMapTileCount` |
| Map buffers & anchors | `wram.asm` | `wOverworldMap`, `wTileMap`/`wAttrMap`, `wOverworldMapAnchor`, `wBGMapAnchor` |
| Object motion | `engine/map_objects.asm` | `object_struct`, `StepVectors`, `NPCStep`, `PlayerStep`, `AddStepVector`, `HandleCurNPCStep` |
| Collision | `home/map.asm`, `home/map_objects.asm`, `engine/npc_movement.asm` | `GetCoordTile`, `GetTileCollision`, `IsNextTileWalkable` |
| Facing | `engine/scripting.asm`, `engine/relative_facing.asm` | `Script_faceplayer`, `GetRelativeFacing`, `OW_*` |
| Wild encounters | `engine/events.asm`, `engine/wildmons.asm`, `engine/tile_events.asm` | `RandomEncounter`, `LoadWildMonData`, `GetMapEncounterRate`, `CheckGrassCollision`, `wMorn/Day/NiteEncounterRate`, `wEncounterRateStage` |
| Coordinate triggers | `home/map.asm` | `RunCurrentMapXYTriggers` |
| Warps | `engine/tile_events.asm`, `home/map.asm`, `engine/map_setup.asm` | `CheckWarpCollision`, `GetDestinationWarpNumber`, `CopyWarpData`, `MapSetupScript_Warp`/`_Door` |
| Connections | `home/map.asm`, `engine/warp_connection.asm`, `engine/map_setup.asm` | `FillMapConnections`, `EnterMapConnection`, `MapSetupScript_Connection` |
| Trainer line of sight | `home/trainer.asm`, `engine/std_scripts.asm` | `CheckTrainerBattle`, `FacingPlayerDistance`, `SeenByTrainerScript`, `TrainerWalkToPlayer` |
| Interaction | `engine/events.asm`, `engine/npc_movement.asm`, `home/map.asm` | `CheckAPressOW`, `CheckFacingObject`, `CheckFacingSign`, `TryReadSign` |
| Hidden items | `event/hidden_item.asm` | `HiddenItemScript`, `SIGNPOST_ITEM` |
| Field moves | `engine/overworld/field_moves.asm` | `CutFunction`, `SurfFunction`, `FlyFunction`, `OWFlash`, `wPlayerState` |
| Cut block-swap | `engine/overworld/field_moves.asm`, `event/field_moves.asm` | `CheckMapForSomethingToCut`, `CutTreeBlockPointers`, `CheckOverworldTileArrays`, `CutDownTreeOrGrass`, `OWCutAnimation`, `wFieldMoveCutTileLocation`/`Replacement`, `wWhichCutAnimation` |
| Start menu | `engine/events.asm`, `engine/startmenu.asm` | `CheckMenuOW`, `StartMenuScript`, `StartMenu` |

---

## Where to Next

You now understand the overworld not as data but as *motion*: a sixty-hertz loop that slides a fixed-centre camera across a self-repainting 32×32 torus, walks every object a pixel at a time, and after each step interrogates the tile underfoot for warps, triggers and wild grass while sweeping the map for any trainer whose orthogonal gaze you have crossed. You have seen how A-presses fan out into NPCs, signposts and hidden items, how HMs reach out of the bag to reshape the world, and how the Start menu freezes everything simply by holding the script VM.

One door has been opened repeatedly but never walked through: the battle. Every wild-grass roll, every trainer who finishes their approach, ends with a script handing control to a completely separate machine — its own data structures, its own turn loop, its own damage formula and AI. That machine is the subject of Chapter 9.
