# Text System & Placeholders

Poképrism uses a **dynamic text substitution system** where placeholders in dialogue are expanded at runtime. This allows you to reference player names, Pokémon names, custom string buffers, and other dynamic data without hardcoding values into text.

---

## Quick Reference

### Player/Rival Names
- `<PLAYER>` — Player's name
- `<RIVAL>` — Rival's name

### Pokémon Names
- `<MON>` — Pokémon name from `wMonOrItemNameBuffer`
- `<EMON>` — Enemy Pokémon nickname
- `<BMON>` — Battle Pokémon nickname (current party member)
- `<PKMN>` or `<POKE>` — Generic "POKéMON" text
- `#` — Shorthand for "POKé" (e.g., "#mon")

### Trainer Names
- `<ENEMY>` — Enemy trainer's name
- `<USER>` — Move user's name in battle
- `<TARGET>` — Move target's name in battle

### String Buffers (Custom Data)
- `<STRBF1>` — String Buffer 1 (`wStringBuffer1`)
- `<STRBF2>` — String Buffer 2 (`wStringBuffer2`)
- `<STRBF3>` — String Buffer 3 (`wStringBuffer3`)
- `<STRBF4>` — String Buffer 4 (`wStringBuffer4`)

### Text Formatting
- `<LINE>` / `<NEXT>` — Explicit line break
- `<CONT>` — Continue text after button press
- `<PARA>` / `<PAGE>` — New paragraph (clears text box)
- `<SCROLL>` — Scroll text mode
- `<DONE>` / `<SDONE>` — End text block
- `<PROMPT>` — Display yes/no prompt
- `<LNBRK>` — Linebreak code
- `@` — Next character (used for conditional branches)

### Special Text
- `<TRNER>` — "TRAINER" string
- `<ROCKET>` — "ROCKET" string
- `<......>` — Six dots
- `<MINB>` — Mon or Item name from buffer

---

## How It Works

Placeholders are **1-byte control codes** compiled into the text data. During text printing, the engine's `TextControlCodeJumptable` maps each code to a handler function that either:

1. **Prints from a fixed location** (e.g., `wPlayerName` for `<PLAYER>`)
2. **Prints from a string buffer** (e.g., `wStringBuffer1` for `<STRBF1>`)
3. **Executes formatting logic** (e.g., `<CONT>` advances to next line)

### Implementation Details

Handlers are defined in [home/text.asm](home/text.asm#L315):

```asm
TextControlCodeJumptable::
	dw PlaceEnemyMonNick        ; "<EMON>"
	dw PlaceStringBuffer1       ; "<STRBF1>"
	dw PlaceStringBuffer2       ; "<STRBF2>"
	dw PlaceStringBuffer3       ; "<STRBF3>"
	dw PlaceStringBuffer4       ; "<STRBF4>"
	dw PlaceEnemysName          ; "<ENEMY>"
	dw PlaceBattleMonNick       ; "<BMON>"
	dw PlacePKMN                ; "<PKMN>"
	...
	dw PrintPlayerName          ; "<PLAYER>"
	dw PrintRivalName           ; "<RIVAL>"
```

Character mappings are in [macros/charmap.asm](macros/charmap.asm) (e.g., `ctxtmap "<PLAYER>", $3f, ...`).

---

## Usage Examples

### 1. Player Name (Hardcoded Placeholder)

```asm
.got_badge_text
	ctxt "<PLAYER> received"
	line "Pyre Badge!"
	done
```

This automatically prints the player's name from `wPlayerName`.

### 2. Conditional Text

The `@` placeholder allows embedding inline Assembly to conditionally branch:

```asm
.temperature_text
	para "Can't handle being"
	line "around steaming"
	para "lava at @"
	start_asm
	ld a, [wOptions2]
	and 1 << 2
	ld hl, .metric_text
	ret z
	ld hl, .imperial_text
	ret
.metric_text
	ctxt "700"
	line "degrees C?"
	done
.imperial_text
	ctxt "1,300"
	line "degrees F?"
	done
```

The Assembly code checks `wOptions2` (temperature units) and returns a pointer to the appropriate text block.

### 3. Dynamic String Buffers

For custom data (gym leader names, city names, item names, etc.), use string buffers:

#### Step 1: Load the data into a string buffer

```asm
MyScript:
	; Load string into wStringBuffer1
	ld de, wStringBuffer1
	ld hl, MyGymLeaderName
	call CopyBytes              ; or memcpy-equivalent
	
	opentext
	writetext MyDialogue
	closetext

MyGymLeaderName:
	db "Josiah", "@"           ; @ terminates the string
```

#### Step 2: Use the placeholder in text

```asm
MyDialogue:
	ctxt "The Gym Leader is <STRBF1>."
	
	para "Can you defeat them?"
	done
```

When displayed, `<STRBF1>` will be replaced with "Josiah".

### 4. Bingo System Example

From [event/bingo.asm](event/bingo.asm#L1742):

```asm
BingoCheckBadgesOwned:
	ld hl, wBadges
	ld b, 0
	ld c, 0
.count_loop
	; Count set bits in badge bitfield
	; Store count in c
	
	ld a, c
	call PrintNumber            ; Result goes to wStringBuffer4
	
	; Now text can use <STRBF4> to display the count
	ctxt "Get <STRBF4> badges."
	done
```

This dynamically inserts the number of badges needed (e.g., "Get 8 badges.").

### 5. Rival & Enemy Names

```asm
RivalScript:
	ctxt "<RIVAL> appeared!"
	
	para "Get 'em, <PLAYER>!"
	done

BattleText:
	ctxt "<ENEMY> sent out <EMON>!"
	done
```

---

## Working with String Buffers

### Available Buffers

| Buffer | Symbol | Size | Use Case |
|--------|--------|------|----------|
| Buffer 1 | `wStringBuffer1` | ? | Gym leaders, NPCs, city names |
| Buffer 2 | `wStringBuffer2` | ? | Item names, Pokémon species |
| Buffer 3 | `wStringBuffer3` | ? | Generic text |
| Buffer 4 | `wStringBuffer4` | ? | Numbers, counts |

### Loading Strings

Use the appropriate copy routine:

```asm
; Copy from ROM
ld de, wStringBuffer1
ld hl, MyTextString      ; ROM address
call CopyBytes

; Or use a predef for special data
; e.g., GetMonName, GetItemName
predef GetMonName, wPartyMon1Species
ld de, wStringBuffer2
; (name now in wMonOrItemNameBuffer, can copy or use directly)
```

### Clearing a Buffer

```asm
ld a, 0
ld [wStringBuffer1], a   ; Clear first byte (null terminator)
```

---

## Text Formatting Codes

### Line Management

```asm
TextBlock1:
	ctxt "First line"
	line "Second line"    ; Continues in same box
	cont "Third line"     ; Also continues
	done                  ; End block
```

### Paragraphs

```asm
TextBlock2:
	ctxt "First paragraph"
	
	para "Second paragraph" ; New box, clears previous
	
	page "Third paragraph"  ; Alias for para
	done
```

### Interrupts & Prompts

```asm
TextBlock3:
	ctxt "Do you want to continue?"
	prompt
	; Player sees yes/no, carry flag set on "yes"
	done
```

---

## Best Practices

1. **Use placeholders for player/rival**: Always use `<PLAYER>` and `<RIVAL>` instead of hardcoding "Blue" or "Red".

2. **Leverage string buffers for reusable data**: Instead of duplicating gym leader names across scripts, load them once into a buffer.

3. **Check buffer size**: Make sure your data fits in the buffer before copying. Overflow can corrupt memory.

4. **Null-terminate strings**: Always end strings with `@` or `0x00` so the text engine knows where to stop.

5. **Use `start_asm` for complex conditionals**: For more than simple flag checks, embed Assembly to keep logic organized.

6. **Document custom buffers**: If using `<STRBF*>` codes, add comments explaining what each buffer contains in that script.

---

## Implementation References

- **Text printing engine**: [home/text.asm](home/text.asm) — Control code handlers and printing logic
- **Character mappings**: [macros/charmap.asm](macros/charmap.asm) — `ctxtmap` definitions for placeholders
- **Text data format**: [docs/data-formats.md](data-formats.md#text-format) — How text blocks compile
- **Script commands**: [docs/maps-and-events.md](maps-and-events.md#common-script-commands) — `opentext`, `writetext`, etc.

---

## Common Patterns

### Pattern: Dynamic NPC Greeting

```asm
NPCScript:
	; Load NPC name into buffer
	ld de, wStringBuffer1
	ld hl, NPCName
	call CopyBytes
	
	opentext
	writetext .greeting_text
	closetext

.greeting_text
	ctxt "Hello! I'm <STRBF1>."
	
	para "Nice to meet you."
	done

NPCName:
	db "Alice", "@"
```

### Pattern: Conditional Badge Message

```asm
GuideScript:
	checkflag ENGINE_HAZEBADGE
	sif true
		jumptext .after_badge
	jumptext .before_badge

.before_badge
	ctxt "You haven't earned"
	line "the Haze Badge yet."
	done

.after_badge
	ctxt "Great work earning"
	line "the Haze Badge!"
	done
```

### Pattern: Number Display

```asm
MoneyScript:
	; Get player money and convert to string
	ld hl, wPlayerMoney
	ld de, wStringBuffer1
	predef PrintNumber  ; or custom routine
	
	opentext
	writetext .money_text
	closetext

.money_text
	ctxt "You have $<STRBF1>."
	done
```

---

## Troubleshooting

**Text doesn't update with placeholder?**
- Ensure the buffer was populated before calling `writetext`
- Verify the string is null-terminated (`@` or `0x00`)

**Text overflows the box?**
- Use `para` or `page` to force a new box
- Shorten the text or use abbreviations
- Split into multiple `ctxt` blocks

**Buffer contains garbage?**
- Check you're copying the right number of bytes
- Verify the source address is in ROM (not WRAM)
- Confirm the source string is null-terminated

**Placeholder appears as a symbol instead of text?**
- The placeholder code may not be mapped in `charmap.asm`
- Add a `ctxtmap` entry for custom codes
- Rebuild the ROM with `make`

