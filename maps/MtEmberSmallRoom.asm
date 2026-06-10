MtEmberSmallRoom_MapScriptHeader:
 ;trigger count
	db 0
 ;callback count
	db 0

MtEmberSmallRoomNPC:
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
	closetextend
	end

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
	person_event SPRITE_MINER, 3, 4, SPRITEMOVEDATA_STANDING_RIGHT, 0, 0, -1, -1, PAL_OW_RED, PERSONTYPE_SCRIPT, 0, MtEmberSmallRoomNPC, -1