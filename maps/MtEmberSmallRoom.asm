MtEmberSmallRoom_MapScriptHeader:
 ;trigger count
	db 0
 ;callback count
	db 1

	dbw MAPCALLBACK_TILES, .remove_stones

; ***** Map callbacks *****
.remove_stones
	checkevent EVENT_KINDLE_ROAD_OPEN
	sif true
		changeblock 2, 2, $6
	return

MtEmberSmallRoomNPC:
	checkevent EVENT_KINDLE_ROAD_OPEN
	; Dynamite guy fight
	sif true, then
		opentext
		writetext .dynamite_fight
		loadtrainer MINER, 7
		winlosstext .dynamite_lost_text, 0
		startbattle
		reloadmapafterbattle
		showtext .dynamite_leaves
		applymovement 2, .dynamite_walks_away
		playsound SFX_ENTER_DOOR
		disappear 2		; Set EVENT_EMBER_DYNAMITE_GUY_LEFT
		end
	sendif
	; Dynamite guy blocks path
	opentext
	checkevent EVENT_EMBER_DYNAMITE_GUY
	sif false, then
		writetext .intro_text
		setevent EVENT_EMBER_DYNAMITE_GUY
	selse
		writetext .bedge_check_text
	sendif
	checkflag ENGINE_HIVEBADGE
	sif false, then
		writetext .no_bedge_text
		closetextend
	sendif
	writetext .lit_the_fuse_text
	closetext
	; Before the explosion sequence
	spriteface 2, DOWN
	pause 48
	spriteface 2, RIGHT
	opentext
	writetext .should_leave
	closetext
	showemote EMOTE_SHOCK, PLAYER, 32
	applymovement PLAYER, .player_moves_back
	spriteface PLAYER, LEFT
	pause 32
	; Countdown
	opentext
	writetext .r_u_ready
	pause 32
	writetext .three
	pause 24
	writetext .two
	pause 24
	writetext .one
	pause 64
	closetext
	; Ka-Boom!!!
	playsound SFX_EGG_BOMB
	earthquake 24
	playsound SFX_EGG_BOMB
	earthquake 24
	playsound SFX_EGG_BOMB
	earthquake 24
	playsound SFX_EGG_BOMB
	earthquake 24
	changeblock 2, 2, $6	; Remove stone
	setevent EVENT_KINDLE_ROAD_OPEN
	end

.r_u_ready
	ctxt "Ready kid?"
	done
.three
	ctxt "Three..."
	done
.two
	ctxt "Two..."
	done
.one
	ctxt "One..."
	done

.player_moves_back
	run_step_right
	run_step_right
	run_step_down
	run_step_down
	run_step_right
	run_step_right
	run_step_right
	run_step_right
	run_step_up
	step_end

.should_leave
	ctxt "Maybe you should"
	line "stay away..."
	sdone

.intro_text
	ctxt "Oh<...> hello!"

	para "I'm trying to get"
	line "to Kindle Road."

	para "This rock is very"
	line "hard, though."

	para "If the devs help"
	line "me, you'll be able"
	para "to travel to"
	line "Kindle Road, and"
	cont "other places too!"
	sdone

.bedge_check_text
	ctxt "So<...>"

	para "Have you beaten"
	line "Bugsy?"
	sdone

.no_bedge_text
	ctxt "<...>"

	para "Nope, can't let"
	line "you pass, kid!"
	sdone

.lit_the_fuse_text
	ctxt "Great!"

	para "Let's blew this"
	line "place out!"
	sdone

.dynamite_fight
	ctxt "Well, that was"
	line "fun!"

	para "Before you go to"
	line "Kindle Road<...>"

	para "How about a good"
	line "<PKMN> battle?"
	sdone

.dynamite_lost_text
	ctxt "Woah!"
	done

.dynamite_leaves
	ctxt "You're a good"
	line "trainer, kid."

	para "Come visit me and"
	line "wife in Kin Island!"
	sdone

.dynamite_walks_away
	step_left
	step_down
	step_down
	step_end

; ***** Event header *****
MtEmberSmallRoom_MapEventHeader:: db 0, 0

.Warps
	db 1
	warp_def $4, $0a, 4, MT_EMBER_ROOM_1

.CoordEvents
	db 0

.BGEvents
	db 0

.ObjectEvents
	db 1
	person_event SPRITE_MINER, 3, 4, SPRITEMOVEDATA_STANDING_RIGHT, 0, 0, -1, -1, PAL_OW_RED, PERSONTYPE_SCRIPT, 0, MtEmberSmallRoomNPC, EVENT_EMBER_DYNAMITE_GUY_LEFT