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

MtEmberWest_Trainer_2:
	trainer EVENT_MT_EMBER_WEST_TRAINER_2, JUGGLER, 5, .before_battle_text, .battle_won_text

	ctxt "BLA BLA BLA"
	line "BLA BLA BLA."
	done

.before_battle_text
	ctxt "BLA BLA BLA"
	line "BLA BLA BLA."
	done

.battle_won_text
	ctxt "BLA BLA BLA"
	line "BLA BLA BLA."
	done

; ***** NPCs *****
MtEmberWest_NPC_1:
	ctxt "Do you see the"
	line "lighthouse there?"

	para "The Guardians dis-"
	line "allowed building"
	cont "it, way back then."

	para "Who knows where"
	line "they are now, or"
	para "if they're even"
	line "still alive<...>"
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
	db 11
	person_event SPRITE_CAMPER, 4, 9, SPRITEMOVEDATA_STANDING_DOWN, 0, 0, -1, -1, 8 + PAL_OW_GREEN, PERSONTYPE_GENERICTRAINER, 3, MtEmberWest_Trainer_1, -1
	person_event SPRITE_MINER, 17, 5, SPRITEMOVEDATA_SPINRANDOM_SLOW, 0, 0, -1, -1, PAL_OW_BLUE, PERSONTYPE_GENERICTRAINER, 0, MtEmberWest_Trainer_2, -1
	person_event SPRITE_GRAMPS, 38, 15, SPRITEMOVEDATA_WALK_LEFT_RIGHT, 1, 2, -1, -1, PAL_OW_RED, PERSONTYPE_TEXTFP, 0, MtEmberWest_NPC_1, -1
	person_event SPRITE_BIRDKEEPER, 44, 13, SPRITEMOVEDATA_SPINRANDOM_FAST, 0, 0, -1, -1, PAL_OW_BLUE, PERSONTYPE_GENERICTRAINER, 0, MtEmberWest_Trainer_2, -1
	person_event SPRITE_CAMPER, 50, 11, SPRITEMOVEDATA_STANDING_UP, 0, 0, -1, -1, 8 + PAL_OW_GREEN, PERSONTYPE_GENERICTRAINER, 3, MtEmberWest_Trainer_1, -1
	person_event SPRITE_COOLTRAINER_F, 54, 16, SPRITEMOVEDATA_STANDING_LEFT, 0, 0, -1, -1, PAL_OW_BLUE, PERSONTYPE_GENERICTRAINER, 0, MtEmberWest_Trainer_2, -1
	person_event SPRITE_HIKER, 59, 5, SPRITEMOVEDATA_SPINRANDOM_SLOW, 0, 0, -1, -1, PAL_OW_GREEN, PERSONTYPE_GENERICTRAINER, 0, MtEmberWest_Trainer_2, -1
	person_event SPRITE_R_BEAUTY, 66, 18, SPRITEMOVEDATA_STANDING_DOWN, 3, 2, -1, -1, PAL_OW_RED, PERSONTYPE_TEXTFP, 0, MtEmberWest_NPC_1, -1
	person_event SPRITE_PICNICKER, 72, 16, SPRITEMOVEDATA_STANDING_LEFT, 0, 0, -1, -1, PAL_OW_GREEN, PERSONTYPE_GENERICTRAINER, 0, MtEmberWest_Trainer_2, -1
	person_event SPRITE_TEACHER, 74, 6, SPRITEMOVEDATA_WANDER, 3, 2, -1, -1, PAL_OW_RED, PERSONTYPE_TEXTFP, 0, MtEmberWest_NPC_1, -1
	person_event SPRITE_R_JUGGLER, 36, 14, SPRITEMOVEDATA_STANDING_RIGHT, 0, 0, -1, -1, PAL_OW_BLUE, PERSONTYPE_TEXTFP, 0, MtEmberWest_NPC_1, -1



