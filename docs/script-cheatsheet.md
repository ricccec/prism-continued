# Script Command Cheatsheet

Quick reference for the map-script bytecode. Every command below is a macro
defined in `macros/event.asm` (movement lists in `macros/movement.asm`, text
formatting in `macros/text.asm`) and interpreted at runtime by
`engine/scripting.asm`. When in doubt about a macro's exact arguments, grep
its `MACRO <name>` block in `macros/event.asm` — that's the ground truth this
sheet was built from.

For the overall map file layout (script header, event header, warps,
objects), see [maps-and-events.md](maps-and-events.md).

---

## Conditionals — there are two unrelated systems

It's easy to mix these up; they are not interchangeable.

### 1. Jump-style: `iftrue` / `iffalse` / `if_equal` / `if_not_equal` / `if_greater_than` / `if_less_than`

Compare against `hScriptVar` (populated by a preceding `check*` command) and
**jump to `<ptr>` if the condition holds**; otherwise execution just falls
through to the next command (no skipping involved).

```asm
checkevent EVENT_FOO
iftrue     .FooIsSet     ; jump there if the flag was set
; otherwise falls through to here
```

```asm
if_equal        <byte>, <ptr>   ; jump if hScriptVar == byte
if_not_equal    <byte>, <ptr>   ; jump if hScriptVar != byte
if_greater_than <byte>, <ptr>   ; jump if hScriptVar > byte
if_less_than    <byte>, <ptr>   ; jump if hScriptVar < byte
```

### 2. `sif` / `selse` / `sendif` — skip-style

`sif <condition>` where `<condition>` is `true`, `false`, `=`/`==`, `!=`/`<>`,
`>`, `<`, `>=`, or `<=` (the parameterized forms also take a byte to compare
against, e.g. `sif >, 5`).

**⚠️ `sif` must be on its own line.** It only recognizes a bare `then` as a
same-line second token — anything else (like jamming the guarded command
onto the same line, e.g. `sif false jumptext .Foo`) gets swallowed whole into
the condition argument, fails every `strcmp` check, and hard-fails the build
with `Invalid condition to sif`. Always write it as:

```asm
sif false
	jumptext .Foo   ; only this one command is skipped if the condition is false
```

- **No `then`**: guards exactly the single next command. False → skip just
  that one command and continue. True → run it normally.
- **With `then` … `sendif`** (optionally with `selse` in between): guards a
  whole block.
  ```asm
  sif true, then
  	writetext .A
  	giveitem ITEM_FOO, 1
  selse
  	writetext .B
  sendif
  ```
  False → skip forward to `selse` (run the else-block) or `sendif` (nothing
  runs). True → run the `then`-block; hitting `selse` while inside it jumps
  past to `sendif` (the else-block is skipped).

### Checking things (feeds `hScriptVar` for either system above)

```asm
checkevent <EVENT_FLAG>     ; event/story flag (constants/event_flags.asm)
checkflag  <ENGINE_FLAG>    ; engine flag — badges, fly points, etc. (constants/engine_flags.asm)
checkitem  <ITEM_*>         ; player has item
checkcode  <var_id>         ; script variable
checkcoins <coins>
checkmoney <account>, <amount>
checktime  <time>
checkpoke  <species>        ; party has species
check_just_battled          ; used after startbattle
comparevartobyte <address>  ; 0/1/2 = var >/</= byte
```

Setting/clearing:
```asm
setevent   <EVENT_FLAG>
clearevent <EVENT_FLAG>
setflag    <ENGINE_FLAG>
clearflag  <ENGINE_FLAG>
```

---

## Control flow

```asm
end            ; end script; pops back to the calling script if this was scall'd, else stops entirely
end_all        ; hard-stop everything regardless of the call stack
scall  <ptr>   ; call a sub-script
return         ; return from a scall'd sub-script (NOT "sreturn")
jump   <ptr>   ; unconditional jump, same bank
farjump <ptr>  ; unconditional jump, different bank (dba)
priorityjump <ptr>  ; queue a script to run next frame, outside the normal flow (e.g. for interrupting overworld events)
jumpstd <predefined_script>  ; jump to one of the shared StdScripts
special <SPECIAL_*>          ; call a hardcoded ASM routine by name
callasm <ptr>                ; call raw ASM (or -1 to no-op)
```

---

## Text / dialogue

```asm
opentext                    ; lock player input, open textbox
writetext  <ptr>             ; queue text into the already-open textbox
waitbutton                  ; wait for A/B press
closetext                    ; close textbox, unlock player
yesorno                      ; yes/no prompt; sets carry on "yes"
repeattext                    ; re-display the last writetext'd text (e.g. after yesorno "no")

jumptext <ptr>                ; opentext + writetext + waitbutton + closetext + end, all-in-one
jumptextfaceplayer <ptr>      ; same as jumptext, but faceplayer first
farjumptext <ptr>             ; jumptext but text pointer is in a different bank (dba)
farwritetext <bank>, <ptr>    ; writetext but text pointer is in a different bank
```

Use `writetext`/`waitbutton`/`closetext` manually when the script needs to do
more after the text (give an item, start a battle, branch, …). Use
`jumptext`/`jumptextfaceplayer` when showing the text is the last thing the
script does.

### Text body formatting (inside a text block, from `macros/text.asm`)

```asm
ctxt "First line"      ; start a compressed text block (huffman-packed)
line "Second line"      ; start writing on the bottom line of the box
cont "continued..."      ; scroll up one line
para "New paragraph"     ; start a fresh paragraph (clears the box)
next "..."                ; move down a line without scrolling
scroll "..."              ; autoscroll to the next line, no button press needed
done                       ; end the text box
sdone                      ; like done, but with a cursorless prompt
prompt                     ; prompt to end textbox, expects another event next (e.g. yesorno)
```

---

## NPC facing & movement

```asm
faceplayer                  ; the talking NPC turns to face the player
faceperson <person1>, <person2>  ; person1 turns to face person2
spriteface <person>, <direction> ; unconditionally set a sprite's facing — direction is a
                                  ; compile-time constant (UP/DOWN/LEFT/RIGHT), not relative
                                  ; to the player. To make an NPC "face away", just pass
                                  ; whichever literal direction is opposite the player's side.
applymovement <person>, <data>   ; run a movement list (see below) on person, blocking
applymovement2 <data>             ; same, but on the last-talked-to person
setlasttalked <person>
deactivatefacing <person>        ; the given person stops auto-facing the player when talked to

; visibility / following
appear <person>
disappear <person>
follow <person1>, <person2>       ; person1 starts following person2
follownotexact <person1>, <person2>
stopfollow <person1>, <person2>
moveperson <person>, <x>, <y>     ; teleport a person to new map coords
writepersonxy <person>, <address> ; store a person's coords into memory
```

`<person>` is `PLAYER` (`0`) or the 1-based index into the map's
`.ObjectEvents` list (the order you declared them with `person_event`).
`<direction>` is `UP`/`DOWN`/`LEFT`/`RIGHT` (`constants/wram_constants.asm`).

### Movement list steps (`macros/movement.asm`, used as `<data>` for `applymovement`)

Most common:
```asm
step_down / step_up / step_left / step_right       ; normal-speed step
slow_step_* / big_step_* / run_step_*                ; other speeds
turn_head_down / turn_head_up / turn_head_left / turn_head_right  ; face only, no step
step_sleep_1 .. step_sleep_8                          ; pause N frames
step_end                                              ; terminator — every list needs one
```
Also available: slide/jump variants (`slide_step_*`, `jump_step_*`,
`fast_jump_step_*`, …), `fix_facing`/`remove_fixed_facing`,
`show_person`/`hide_person`, `step_dig`, `tree_shake`, `rock_smash`. See
`macros/movement.asm` for the full list.

---

## Trainer battles

```asm
loadtrainer <TRAINER_CLASS>, <id>   ; load a trainer's party
winlosstext <win_ptr>, <loss_ptr>   ; text shown after winning / losing
startbattle                          ; start the battle
reloadmapafterbattle                 ; redraw the map when the battle ends
end_if_just_battled                  ; short-circuit the rest of the script if we just fought
check_just_battled                    ; feeds hScriptVar for the conditionals above
scripttalkafter                       ; re-run this script's talk-after logic
trainertext <n>                       ; pick from the trainer's canned taunt/rematch lines
trainerflagaction <action>            ; manipulate the trainer's beaten-flag directly
```

Trainer object events point at a data block built with the `trainer` macro
(`macros/trainer.asm`), not a script command:
```asm
MyTrainer_1:
	trainer EVENT_FLAG, TRAINER_CLASS, id, .SeenText, .WinText[, .AlreadyBeatenText]
```

---

## Items, money, Pokémon

```asm
giveitem  <ITEM_*>[, qty]     ; default qty 1
takeitem  <ITEM_*>[, qty]
verbosegiveitem <ITEM_*>[, qty]   ; giveitem + "received X" message + pocket-full handling
givemoney <account>, <amount>
takemoney <account>, <amount>
givecoins <n>
takecoins <n>
givepoke  <species>, <level>[, <item>[, <trainer_flag>, <name_ptr>, <nickname_ptr>]]
giveegg   <species>, <level>
givetm    <TM_id>
```

---

## Warps & map control

```asm
warp        <MAP_CONST>, <x>, <y>       ; teleport the player
warpfacing  <direction>, <MAP_CONST>, <x>, <y>   ; teleport and face a direction on arrival
warpmod     <warp_id>, <MAP_CONST>       ; retarget an existing warp_def at runtime
changemap   <MAP_CONST>                   ; swap the current map data without a full warp
changeblock <x>, <y>, <block_id>          ; change a single metatile block
reloadmap                                  ; redraw the current map
```

---

## Variables

```asm
setvar / loadvar <address>, <value>
copybytetovar <address>       ; byte at address -> hScriptVar
copyvartobyte <address>       ; hScriptVar -> byte at address
addvar <value>                ; add to hScriptVar
random [<max>]                ; random byte into hScriptVar
```

---

## Known gotchas

- `sif`/`then`/`selse`/`sendif` is a completely different mechanism from
  `iftrue`/`iffalse`/`if_equal`/etc — don't mix vocabulary between them.
- `sif` never accepts a command on the same line except the literal word
  `then`. Always split it across two lines.
- `checkevent` is for **story/event flags** (`EVENT_*`); `checkflag` is for
  **engine flags** (`ENGINE_*`, badges/fly points/etc) — different constant
  namespaces, easy to typo one for the other.
- `return` (not `sreturn`) is the command that returns from a `scall`.
