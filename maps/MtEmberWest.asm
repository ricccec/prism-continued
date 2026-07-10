MtEmberWest_MapScriptHeader::
 ;trigger count
	db 0
 ;callback count
	db 0

; ***** Event header *****
MtEmberWest_MapEventHeader:: db 0, 0

.Warps
	db 1
	warp_def 5, 14, 2, MT_EMBER_SMALL_ROOM

.CoordEvents
	db 0

.BGEvents
	db 1
	signpost 19,  7, SIGNPOST_LOAD, MtEmberWestDirectionsSign

.ObjectEvents
	db 12
	person_event SPRITE_CAMPER, 4, 9, SPRITEMOVEDATA_STANDING_DOWN, 0, 0, -1, -1, 8 + PAL_OW_GREEN, PERSONTYPE_GENERICTRAINER, 3, MtEmberWest_Trainer_1, -1
	person_event SPRITE_MINER, 17, 5, SPRITEMOVEDATA_SPINRANDOM_SLOW, 0, 0, -1, -1, PAL_OW_BLUE, PERSONTYPE_GENERICTRAINER, 0, MtEmberWest_Trainer_2, -1
	person_event SPRITE_GRAMPS, 38, 15, SPRITEMOVEDATA_WALK_LEFT_RIGHT, 1, 2, -1, -1, PAL_OW_RED, PERSONTYPE_TEXTFP, 0, MtEmberWest_NPC_1, -1
	person_event SPRITE_BIRDKEEPER, 44, 13, SPRITEMOVEDATA_SPINRANDOM_FAST, 0, 0, -1, -1, PAL_OW_BLUE, PERSONTYPE_GENERICTRAINER, 0, MtEmberWest_Trainer_3, -1
	person_event SPRITE_CAMPER, 50, 11, SPRITEMOVEDATA_STANDING_UP, 0, 0, -1, -1, 8 + PAL_OW_GREEN, PERSONTYPE_GENERICTRAINER, 3, MtEmberWest_Trainer_4, -1
	person_event SPRITE_COOLTRAINER_F, 54, 16, SPRITEMOVEDATA_STANDING_LEFT, 0, 0, -1, -1, PAL_OW_BLUE, PERSONTYPE_GENERICTRAINER, 0, MtEmberWest_Trainer_5, -1
	person_event SPRITE_HIKER, 59, 5, SPRITEMOVEDATA_SPINRANDOM_SLOW, 0, 0, -1, -1, PAL_OW_GREEN, PERSONTYPE_GENERICTRAINER, 0, MtEmberWest_Trainer_6, -1
	person_event SPRITE_R_BEAUTY, 66, 18, SPRITEMOVEDATA_STANDING_DOWN, 3, 2, -1, -1, PAL_OW_RED, PERSONTYPE_TEXTFP, 0, MtEmberWest_NPC_2, -1
	person_event SPRITE_PICNICKER, 72, 16, SPRITEMOVEDATA_STANDING_LEFT, 0, 0, -1, -1, PAL_OW_GREEN, PERSONTYPE_GENERICTRAINER, 0, MtEmberWest_Trainer_7, -1
	person_event SPRITE_TEACHER, 74, 6, SPRITEMOVEDATA_WANDER, 3, 2, -1, -1, PAL_OW_RED, PERSONTYPE_TEXTFP, 0, MtEmberWest_NPC_3, -1
	person_event SPRITE_R_JUGGLER, 36, 14, SPRITEMOVEDATA_STANDING_RIGHT, 0, 0, -1, -1, PAL_OW_BLUE, PERSONTYPE_SCRIPT, 0, MtEmberWest_Script_Juggler, -1
	person_event SPRITE_POKE_BALL, 49, 4, SPRITEMOVEDATA_ITEM_TREE, 0, 0, -1, -1, PAL_OW_RED, PERSONTYPE_ITEMBALL, 2, HYPER_POTION, EVENT_MT_EMBER_WEST_ITEM_1

; ***** Map callbacks *****

; ***** Scripts *****

MtEmberWest_Script_Juggler:
	; After prize given dialogue
	checkevent EVENT_GOT_PRIZE_FROM_MT_EMBER_WEST_JUGGLER
	sif true
		jumptextfaceplayer .AfterText2
	; Gave prize dialogue
	checkevent EVENT_MT_EMBER_WEST_JUGGLER_BEATEN
	sif true
		jump .Beaten
	; Check all trainers have been beaten
	checkevent EVENT_MT_EMBER_WEST_TRAINER_1
	sif false
		jumptextfaceplayer .IntroText
	checkevent EVENT_MT_EMBER_WEST_TRAINER_2
	sif false
		jumptextfaceplayer .IntroText
	checkevent EVENT_MT_EMBER_WEST_TRAINER_3
	sif false
		jumptextfaceplayer .IntroText
	checkevent EVENT_MT_EMBER_WEST_TRAINER_4
	sif false
		jumptextfaceplayer .IntroText
	checkevent EVENT_MT_EMBER_WEST_TRAINER_5
	sif false
		jumptextfaceplayer .IntroText
	checkevent EVENT_MT_EMBER_WEST_TRAINER_6
	sif false
		jumptextfaceplayer .IntroText
	checkevent EVENT_MT_EMBER_WEST_TRAINER_7
	sif false
		jumptextfaceplayer .IntroText
	; All trainers beaten: prompt battle
	opentext
	writetext .QuestionText
	yesorno
	sif false
		jumptext .RefusedText
	; Start battle
	writetext .BeforeBattleText
	waitbutton
	closetext
	loadtrainer JUGGLER, 5
	winlosstext .BeatenText, 0
	startbattle
	reloadmapafterbattle
	setevent EVENT_MT_EMBER_WEST_JUGGLER_BEATEN
.Beaten:
	faceplayer
	opentext
	writetext .GivePrizeText
	;promptbutton
	;verbosegiveitem PROTECT_PADS
	;iffalse_endtext
	setevent EVENT_GOT_PRIZE_FROM_MT_EMBER_WEST_JUGGLER
	closetext
	end

.IntroText:
	ctxt "As a Battle Girl,"
	line "I train intensely"
	cont "every day."

	para "There's something"
	line "intense about you."

	para "Can you beat all"
	line "the trainers in"
	cont "this Lighthouse?"

	para "If you can, then"
	line "I will battle you."
	done

.QuestionText:
	ctxt "So you've bested"
	line "this entire tower?"

	para "Then you have one"
	line "opponent left--"
	cont "Chuck's own stu-"
	cont "dent--me!"

	para "Ready to spar?"
	done

.RefusedText:
	ctxt "Back to training"
	line "on my own…"
	done

.BeforeBattleText:
	ctxt "From behind my"
	line "Protect Pads, I"
	cont "attack! Ki-yaah!"
	done

.BeatenText:
	ctxt "You broke through"
	line "my defense!"
	done

.GivePrizeText:
	ctxt "Your team is"
	line "formidable!"

	para "But you can become"
	line "even stronger."

	para "These Protect Pads"
	line "will let you make"

	para "contact with your"
	line "opponent without"
	cont "being harmed."
	done

.AfterText2:
	ctxt "One of the Elite"
	line "Four, Bruno, is a"
	cont "fighter like me."

	para "To become as"
	line "strong as him--"
	cont "that's my aim."
	done

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
	trainer EVENT_MT_EMBER_WEST_TRAINER_2, MINER, 7, .before_battle_text, .battle_won_text

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

MtEmberWest_Trainer_3:
	trainer EVENT_MT_EMBER_WEST_TRAINER_3, MINER, 7, .before_battle_text, .battle_won_text

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

MtEmberWest_Trainer_4:
	trainer EVENT_MT_EMBER_WEST_TRAINER_4, MINER, 7, .before_battle_text, .battle_won_text

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

MtEmberWest_Trainer_5:
	trainer EVENT_MT_EMBER_WEST_TRAINER_5, MINER, 7, .before_battle_text, .battle_won_text

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

MtEmberWest_Trainer_6:
	trainer EVENT_MT_EMBER_WEST_TRAINER_6, MINER, 7, .before_battle_text, .battle_won_text

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

MtEmberWest_Trainer_7:
	trainer EVENT_MT_EMBER_WEST_TRAINER_7, MINER, 7, .before_battle_text, .battle_won_text

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
	ctxt "Have you seen that"
	line "tree blocking the"
	cont "path?"

	para "Apparently these"
	line "days you could"
	cont "cut it"

	para "even if none of"
	line "your #mon"
	cont "knows the move."

	para "What a time to be"
	line "alive!"
	done

MtEmberWest_NPC_2:
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

MtEmberWest_NPC_3:
	ctxt "I've lost an item"
	line "on the beach"
	cont "earlier."

	para "But while I was"
	line "looking for it"

	para "I found something"
	line "else!"
	done

; ***** BG events *****
MtEmberWestDirectionsSign:
	ctxt "<DOWN><RIGHT> Kindle Road"
	next "<DOWN><DOWN> One Island"
	done
	