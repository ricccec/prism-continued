MtEmberSmallRoom_MapScriptHeader:
 ;trigger count
	db 0
 ;callback count
	db 0

MtEmberSmallRoomNPC:
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
	done

; ***** Event header *****
MtEmberSmallRoom_MapEventHeader:: db 0, 0

.Warps
	db 1
	warp_def $5, $5, 4, MT_EMBER_ROOM_1

.CoordEvents
	db 0

.BGEvents
	db 0

.ObjectEvents
	db 1
	person_event SPRITE_MINER, 2, 3, SPRITEMOVEDATA_STANDING_DOWN, 0, 0, -1, -1, PAL_OW_RED, PERSONTYPE_TEXTFP, 0, MtEmberSmallRoomNPC, -1