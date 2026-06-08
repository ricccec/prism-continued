MtEmberSmallRoom_MapScriptHeader:
 ;trigger count
	db 0
 ;callback count
	db 0

MtEmberSmallRoom_MapEventHeader:: db 0, 0

.Warps
	db 3
	warp_def $10, $c, 2, MT_EMBER_ENTRANCE
	warp_def $11, $2, 1, MT_EMBER
	warp_def $11, $3, 1, MT_EMBER

.CoordEvents
	db 0

.BGEvents
	db 0

.ObjectEvents
	db 0