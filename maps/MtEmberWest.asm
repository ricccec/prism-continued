MtEmberWest_MapScriptHeader:
 ;trigger count
	db 0
 ;callback count
	db 0

; ***** Map callbacks *****

; ***** Trainers *****

MtEmberWest_Trainer_1:
	trainer EVENT_MT_EMBER_WEST_TRAINER_1, CAMPER, 5, .before_battle_text, .battle_won_text

	ctxt "BLA BLA BLA"
	line "BLA BLA BLA."
	done

.before_battle_text
	ctxt "I climbed all the"
	line "way up here just"
	cont "to catch a rare"
	cont "#mon!"
	done

.battle_won_text
	ctxt "I should have"
	line "stayed at the beach"
	done


; ***** Event header *****
MtEmberWest_MapEventHeader:: db 0, 0

.Warps
	db 1
	warp_def 5, 14, 2, MT_EMBER_SMALL_ROOM

.CoordEvents
	db 0

.BGEvents
	db 0

.ObjectEvents
	db 1
	person_event SPRITE_CAMPER, 4, 9, SPRITEMOVEDATA_STANDING_DOWN, 0, 0, -1, -1, 8 + PAL_OW_GREEN, PERSONTYPE_GENERICTRAINER, 3, MtEmberWest_Trainer_1, -1
