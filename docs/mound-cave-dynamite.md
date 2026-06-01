# Mound Cave Dynamite Guy

`maps/MoundF1.asm` — sprite 3 (`SPRITE_R_HIKER`), dismissed by `EVENT_BLEW_UP_DYNAMITE`.

## Overview

The dynamite guy blocks the cave exit until the player hands him 5 Dynamite and lights the fuse with a Fire-type Pokémon or move. Completing the sequence permanently swaps the map's block layout to a blown-up version and removes the NPC.

## Map callback

```asm
dbw MAPCALLBACK_TILES, .swap_map

.swap_map
    checkevent EVENT_BLEW_UP_DYNAMITE
    sif true
        changemap MoundF1_BlownUp_BlockData
    return
```

`MAPCALLBACK_TILES` runs every time the map loads. Once `EVENT_BLEW_UP_DYNAMITE` is set, `changemap` redirects the block data pointer to `MoundF1_BlownUp_BlockData` (inlined at the bottom of the file as a compressed `.ablk.lz` blob). This makes the post-explosion layout permanent: the engine sees the replacement block data as the map's actual terrain from that point on.

## Script flow

### 1. First-talk intro

```asm
checkevent EVENT_SPOKE_DYNAMITE_GUY
sif false, then
    writetext .intro_text
    setevent EVENT_SPOKE_DYNAMITE_GUY
sendif
```

One-time intro. Subsequent talks skip straight to the item check.

### 2. Dynamite check — takeitem as a quantity probe

```asm
takeitem DYNAMITE, 5
sif false, then
    checkitem POKE_BALL
    sif true, then
        writetext .theres_dynamite_left_text
        jumptext .still_waiting_text        ; exits
    selse
        writetext .no_balls_text
        verbosegiveitem POKE_BALL, 3        ; gives balls to catch Pokémon with
        closetextend                        ; exits
    sendif
sendif
giveitem DYNAMITE, 5
```

`takeitem` removes items from the bag and sets `hScriptVar` to false if the player didn't have enough. Both branches of the `sif false` block exit the script via `jumptext` or `closetextend`, so `giveitem DYNAMITE, 5` is only reached on success — it immediately restores the 5 Dynamite. The script uses this take-then-restore pattern because `checkitem` doesn't support a quantity argument; `takeitem` is the only way to verify the player has a specific count without committing to consuming them yet.

If the player has no Poké Ball at all on first failure, the guy gives them 3 to help catch Electric and Fire Pokémon needed to traverse the cave.

### 3. Fire-type check and mon selection

```asm
giveitem DYNAMITE, 5
writetext .need_fire_mon_text
findpokemontype FIRE
waitbutton
sif false
    closetextend
getpartymonname 0
writetext .try_mon_text          ; "Try with <NAME>?"
addvar -1
copyvartobyte wCurPartyMon
yesorno
closetext
sif false
    end
```

`findpokemontype FIRE` scans the party for any Pokémon whose primary/secondary type is Fire, or that knows a Fire-type move. It stores a 1-based party index (1–6) in `hScriptVar`, or 0 if nothing qualifies. The `sif false` exits with no dynamite consumed if the player has no eligible Pokémon.

`getpartymonname 0` — the argument `0` tells the command to read from `hScriptVar` rather than a literal index. Since `findpokemontype` left the 1-based party slot there, `addvar -1` converts to 0-based, and `copyvartobyte wCurPartyMon` stores it so `fieldmovepokepic` knows which mon to show.

`yesorno` lets the player confirm or back out. Saying No exits without consuming anything.

### 4. Explosion sequence

```asm
fieldmovepokepic                          ; show the selected mon's picture
showtext .lit_the_fuse_text
applymovement PLAYER, .player_steps_aside
applymovement 3, .guy_steps_aside
applymovement 3, .guy_moves_back
showemote EMOTE_SHOCK, PLAYER, 32
applymovement PLAYER, .player_moves_back
changemap MoundF1_BlownUp_BlockData       ; swap block data before the shaking
playsound SFX_EGG_BOMB
earthquake 24
playsound SFX_EGG_BOMB
earthquake 24
playsound SFX_EGG_BOMB
earthquake 24
playsound SFX_EGG_BOMB
earthquake 24
spriteface 3, UP
spriteface PLAYER, LEFT
showemote EMOTE_HAPPY, 3, 32
showtext .after_blowing_up_text
playsound SFX_JUMP_OVER_LEDGE
applymovement 3, .guy_leaves
takeitem DYNAMITE, 5                      ; permanently remove the dynamite
disappear 3                               ; removes sprite, sets EVENT_BLEW_UP_DYNAMITE
end
```

`changemap` happens **before** the earthquake sounds, not after. The terrain update is instant and invisible during the shaking; doing it afterwards would produce a visible pop once the screen settles. The four `SFX_EGG_BOMB` + `earthquake 24` pairs run sequentially for a sustained rumble effect.

`disappear 3` is what sets `EVENT_BLEW_UP_DYNAMITE` as a side effect — the engine records the disappearance event for the sprite. The map callback picks this up on every subsequent load and re-applies the block swap.

The final `takeitem DYNAMITE, 5` is the actual permanent removal. Dynamite is only consumed here, at the point of no return, after all animation and confirmation has passed.
