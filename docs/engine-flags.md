# Engine Flags System

Engine flags are **single-bit status variables** that track persistent game state (badges, completed tasks, learned moves, unlocked features, etc.). Unlike event flags which are binary on/off markers for story progression, engine flags map to specific bits in WRAM variables and are checked frequently during gameplay.

---

## Quick Reference

### Badge Flags

#### Naljo Region (8 badges)
- `ENGINE_PYREBADGE` — Pyre Badge (Oxalis City)
- `ENGINE_NATUREBADGE` — Nature Badge
- `ENGINE_CHARMBADGE` — Charm Badge
- `ENGINE_MIDNIGHTBADGE` — Midnight Badge
- `ENGINE_MUSCLEBADGE` — Muscle Badge
- `ENGINE_HAZEBADGE` — Haze Badge (Acania)
- `ENGINE_RAUCOUSBADGE` — Raucous Badge
- `ENGINE_NALJOBADGE` — Naljo Badge

#### Rijon Region (8 badges)
- `ENGINE_MARINEBADGE` — Marine Badge
- `ENGINE_HAILBADGE` — Hail Badge
- `ENGINE_SPROUTBADGE` — Sprout Badge
- `ENGINE_SPARKYBADGE` — Sparky Badge
- `ENGINE_FISTBADGE` — Fist Badge
- `ENGINE_PSIBADGE` — Psi Badge
- `ENGINE_WHITEBADGE` — White Badge
- `ENGINE_STARBADGE` — Star Badge

#### Other Badges
- `ENGINE_HIVEBADGE` — Hive Badge
- `ENGINE_PLAINBADGE` — Plain Badge
- `ENGINE_MARSHBADGE` — Marsh Badge (gates Magikarp Caverns)
- `ENGINE_BLAZEBADGE` — Blaze Badge

### Status Flags

**HM Abilities** (bits in `wStatusFlags`)
- `ENGINE_FLASH` — Flash move available
- `ENGINE_POKEDEX` — Pokédex acquired
- `ENGINE_POKEMON_MODE` — Pokémon-only mode active
- `ENGINE_POKERUS` — Pokérus infection
- `ENGINE_CREDITS_SKIP` — Skip credits flag

**Bike/Movement** (bits in `wBikeFlags`)
- `ENGINE_STRENGTH_ACTIVE` — Strength move active
- `ENGINE_ALWAYS_ON_BIKE` — Always riding bike
- `ENGINE_DOWNHILL` — Cycling road (downhill)

**Other Mechanics**
- `ENGINE_DAYCARE_MAN_HAS_MON` — Pokémon in daycare
- `ENGINE_DAYCARE_MAN_HAS_EGG` — Egg is ready
- `ENGINE_MOM_SAVING_MONEY` — Money being saved at bank
- `ENGINE_DST` — Daylight saving time
- `ENGINE_BUG_CONTEST_ON` — Bug-catching contest active
- `ENGINE_RTC_TIMERS_ENABLED` — Daily/recurring timers

---

## How Engine Flags Work

Each engine flag is defined in [constants/engine_flags.asm](constants/engine_flags.asm) with:
1. A **name** (constant)
2. A **WRAM byte** it maps to
3. A **bit index** (0–7) within that byte

### Definition Syntax

```asm
def_engine_flag ENGINE_PYREBADGE, wNaljoBadges, 0 ; $18
def_engine_flag ENGINE_NATUREBADGE, wNaljoBadges, 1
def_engine_flag ENGINE_CHARMBADGE, wNaljoBadges, 2
```

This means:
- `ENGINE_PYREBADGE` = bit 0 of `wNaljoBadges` (WRAM $18)
- `ENGINE_NATUREBADGE` = bit 1 of `wNaljoBadges`
- `ENGINE_CHARMBADGE` = bit 2 of `wNaljoBadges`

All 8 Naljo badges fit in a single byte (8 bits).

### Implementation in Code

Under the hood, engine flags are handled by:
- **`CheckFlag`** ([home/flag.asm](home/flag.asm#L64)) — Read a flag bit
- **`SetFlag`** — Set a flag bit to 1
- **`ClearFlag`** — Set a flag bit to 0

In Assembly:
```asm
ld a, [wNaljoBadges]
set BIT_BADGE1, a          ; Set bit 1
ld [wNaljoBadges], a       ; Write back
```

---

## Script Commands

### `checkflag` — Test if a flag is set

Reads a flag and sets the Z flag (zero flag) in the CPU. Use with `sif true` or `sif false` to branch.

**Syntax:**
```asm
checkflag ENGINE_FLAG
sif true
	; Execute if flag is SET
sif false
	; Execute if flag is NOT set
```

**Example: Badge-gated dialogue**

```asm
OxalisGymGuide:
	checkflag ENGINE_PYREBADGE
	sif true
		jumptextfaceplayer .after_badge_text
	jumptextfaceplayer .before_badge_text

.before_badge_text
	ctxt "Alright, Josiah"
	line "has fire #mon,"
	para "but you can tell"
	line "by the scenery,"
	cont "right? Blazing!"
	done

.after_badge_text
	ctxt "Good job!"
	line "You couldn't have"
	cont "done it without my"
	cont "advice, though!"
	done
```

### `setflag` — Set a flag to 1

**Syntax:**
```asm
setflag ENGINE_FLAG
```

**Example: Award a badge after gym battle**

```asm
OxalisGymLeader:
	faceplayer
	checkflag ENGINE_PYREBADGE
	sif true
		jumptext .already_battled_text
	showtext .before_battle_text
	winlosstext .battle_won_text, 0
	loadtrainer JOSIAH, JOSIAH_GYM
	startbattle
	reloadmapafterbattle
	opentext
	writetext .got_badge_text
	playwaitsfx SFX_TCG2_DIDDLY_5
	setflag ENGINE_PYREBADGE       ; Award the badge
	setevent EVENT_ROUTE_73_GUARD
	setevent EVENT_LINK_OPEN
	writetext .before_giving_TM_text
	givetm TM_WILL_O_WISP + RECEIVED_TM
	jumptext .after_giving_TM_text
```

### `clearflag` — Set a flag to 0

**Syntax:**
```asm
clearflag ENGINE_FLAG
```

**Example: Remove a badge (rare, for debugging or special events)**

```asm
ResetBadge:
	clearflag ENGINE_HAZEBADGE
	opentext
	writetext .badge_removed_text
	closetext
```

---

## Real-World Examples

### Example 1: Badge Requirement Gate

Some areas require a specific badge to access. Check before allowing warp:

```asm
MagikarpCavernsEntrance:
	script_xor .require_badge
	db PLAYER_STEP_ON_WARP_TILE_EVENT, WARP_TILE, 3

.require_badge
	checkflag ENGINE_MARSHBADGE
	sif false
		jumptextfaceplayer .need_badge_text
	warp MAGIKARP_CAVERNS_MAIN, 0

.need_badge_text
	ctxt "Sorry! You need"
	line "the Marsh Badge"
	cont "to enter here."
	done
```

### Example 2: Conditional Behavior Based on Badge

In [AcaniaGym.asm](maps/AcaniaGym.asm#L18):

```asm
AcaniaGymGuide:
	checkflag ENGINE_HAZEBADGE
	sif true
		jumptextfaceplayer .after_badge_text
	jumptextfaceplayer .intro_text

.intro_text
	ctxt "This Gym Leader's"
	line "name is Ayaka."

	para "She specializes"
	line "in Gas-types."

	para "Do refrain from"
	line "breathing too"
	cont "much in here<...>"
	done

.after_badge_text
	ctxt "Great, you managed"
	line "to defeat her."

	para "But sadly, the"
	line "horrible scent of"
	cont "this Gym remains!"
	done
```

### Example 3: Check Multiple Badges

```asm
EliteTrainer:
	checkflag ENGINE_STARBADGE
	sif false
		jumptext .need_badges_text
	
	checkflag ENGINE_HAILBADGE
	sif false
		jumptext .need_badges_text
	
	; Both badges present
	jumptext .ready_for_battle_text

.need_badges_text
	ctxt "You need 8 badges"
	line "to challenge me!"
	done

.ready_for_battle_text
	ctxt "You're ready!"
	line "Let's battle!"
	done
```

### Example 4: From Bingo System

Dynamically count earned badges:

```asm
BingoCheckBadgesOwned:
	ld hl, wBadges             ; Johto badges
	ld b, 0
	ld c, 0
.count_loop
	ld a, [hl]
	and 1
	add c
	ld c, a
	...
	; Count bits set, store in c
	
	; Convert count to string buffer
	ld a, c
	call PrintNumber           ; Puts result in wStringBuffer4
	
	ctxt "Get <STRBF4> badges"  ; Displays: "Get 8 badges"
	done
```

---

## Badge Storage Layout

### Naljo Badges (`wNaljoBadges` — WRAM $18)
```
Bit 0: Pyre Badge     (ENGINE_PYREBADGE)
Bit 1: Nature Badge   (ENGINE_NATUREBADGE)
Bit 2: Charm Badge    (ENGINE_CHARMBADGE)
Bit 3: Midnight Badge (ENGINE_MIDNIGHTBADGE)
Bit 4: Muscle Badge   (ENGINE_MUSCLEBADGE)
Bit 5: Haze Badge     (ENGINE_HAZEBADGE)
Bit 6: Raucous Badge  (ENGINE_RAUCOUSBADGE)
Bit 7: Naljo Badge    (ENGINE_NALJOBADGE)
```

### Rijon Badges (`wRijonBadges` — WRAM $20)
```
Bit 0: Marine Badge   (ENGINE_MARINEBADGE)
Bit 1: Hail Badge     (ENGINE_HAILBADGE)
Bit 2: Sprout Badge   (ENGINE_SPROUTBADGE)
Bit 3: Sparky Badge   (ENGINE_SPARKYBADGE)
Bit 4: Fist Badge     (ENGINE_FISTBADGE)
Bit 5: Psi Badge      (ENGINE_PSIBADGE)
Bit 6: White Badge    (ENGINE_WHITEBADGE)
Bit 7: Star Badge     (ENGINE_STARBADGE)
```

### Other Badges (`wOtherBadges` — WRAM $28)
```
Bit 0: Hive Badge     (ENGINE_HIVEBADGE)
Bit 1: Plain Badge    (ENGINE_PLAINBADGE)
Bit 2: Marsh Badge    (ENGINE_MARSHBADGE)
Bit 3: Blaze Badge    (ENGINE_BLAZEBADGE)
Bit 4-7: Unused
```

---

## Badge-Related Mechanics

### Stat Boost from Badges

Badges grant Pokémon stat multipliers. See [battle/badge_boosts.asm](../battle/badge_boosts.asm) for calculations.

### Move Authentication

Some moves require specific badges to use outside battle:

```asm
; Flash requires a badge to use
ld a, [wStatusFlags]
bit ENGINE_FLASH, a
jr z, .cant_use_flash
```

### HM Move Authorization

HM moves (Strength, Waterfall, etc.) similarly check badges before allowing use in the overworld.

---

## Common Patterns

### Pattern: Award Multiple Badges

If a special event grants multiple badges at once:

```asm
SpecialEvent:
	setflag ENGINE_PYREBADGE
	setflag ENGINE_NATUREBADGE
	setflag ENGINE_CHARMBADGE
	opentext
	writetext .got_three_badges_text
	closetext
```

### Pattern: Check Badge & Update Counter

```asm
CheckForNewBadges:
	ld a, [wNaljoBadges]
	ld b, a
	ld c, 0               ; Counter
	
	; Count set bits
	bit 0, b
	jr z, .skip1
	inc c
.skip1
	bit 1, b
	jr z, .skip2
	inc c
.skip2
	; ... continue for all 8 badges
	
	ld [wBadgeCount], c
```

### Pattern: Prevent Badge Removal (Safeguard)

```asm
; Ensure badges don't get cleared accidentally
SafeguardBadges:
	ld a, [wNaljoBadges]
	or %11111111          ; Ensure all bits stay set
	ld [wNaljoBadges], a
```

---

## Difference: Engine Flags vs. Event Flags

| Aspect | Engine Flags | Event Flags |
|--------|--------------|------------|
| **Storage** | Single bits in WRAM bytes | Separate bitfield in SRAM |
| **Scope** | Game mechanics, status | Story progression, quests |
| **Persistence** | Persists while playing | Saved to cartridge battery |
| **Speed** | Very fast (bit test) | Slower (lookup table) |
| **Example** | Badge ownership | "Defeated Gym Leader" |
| **Check Command** | `checkflag` | `checkevent` |

**When to use:**
- **Engine flags** — Temporary game state, badges, active status
- **Event flags** — Story milestones, permanent quest progress

---

## Best Practices

1. **Always use named constants**: Never hardcode bit positions. Use `ENGINE_PYREBADGE` instead of bit 0 of byte $18.

2. **Check badges before gating content**: Always verify the flag before allowing access to badge-required areas.

3. **Award badges immediately after battle**: Set the flag right after a gym leader defeat to prevent softlocks.

4. **Use consistent naming**: Badge constant names should match their in-game names for clarity.

5. **Document custom flags**: If adding new engine flags, add comments explaining what they track.

6. **Avoid flag persistence bugs**: Engine flags are NOT automatically saved to SRAM. If you need persistence across saves, use event flags instead.

7. **Test badge removal**: If a script clears badges (rare), verify it doesn't break subsequent content.

---

## Implementation References

- **Flag definitions**: [constants/engine_flags.asm](constants/engine_flags.asm) — All engine flag constants
- **Flag checking**: [home/flag.asm](home/flag.asm#L64) — `CheckFlag`, `SetFlag`, `ClearFlag` routines
- **Badge stat boosts**: [battle/badge_boosts.asm](../battle/badge_boosts.asm) — Badge effect calculations
- **Script engine**: [engine/engine_flags.asm](../engine/engine_flags.asm) — Script execution for flag commands
- **Memory layout**: [docs/memory-layout.md](memory-layout.md#wram-variables) — WRAM badge variable addresses

---

## Troubleshooting

**Badge flag doesn't persist after loading a save?**
- Engine flags are WRAM-based and not automatically saved to SRAM
- If you need persistence, use event flags (`setevent`, `checkevent`) instead
- Or manually copy WRAM to SRAM during save

**Badge gate isn't working?**
- Verify the gym leader script calls `setflag ENGINE_BADGE` after battle
- Ensure the gate script uses `checkflag` (not `checkevent`)
- Test manually in the emulator debugger

**Badge appears in menu but script doesn't see it?**
- Confirm you're checking the correct badge constant
- Verify the WRAM byte is correct (might be zeroed on load)
- Check for typos in flag name

**Multiple scripts checking the same badge create conflicts?**
- This is actually fine—multiple scripts can read the same flag
- Only one script should **set** the flag (prevent race conditions)
- Use mutual exclusion if needed

