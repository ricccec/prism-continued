INCLUDE "macros/enum.asm"
INCLUDE "constants/landmark_constants.asm"

; OR'ing a landmark ID with $80 (e.g. `KINDLE_ROAD | $80`) marks it as the
; anchor cell, i.e. the one where the cursor/name label will appear on the map
;screen.
; Player-facing landmark names are defined in engine/landmarks.asm

; x, y, landmark ID
MACRO landmark
	DEF x = \1
	DEF y = \2
	DEF ___landmark_{d:x}_{d:y} = \3
ENDM

MACRO end_landmarks
	for y, LANDMARK_MAP_HEIGHT
		for x, LANDMARK_MAP_WIDTH
			if DEF(___landmark_{d:x}_{d:y})
				db ___landmark_{d:x}_{d:y}
				PURGE ___landmark_{d:x}_{d:y}
			else
				db $ff
			endc
		endr
	endr
ENDM

SECTION "Landmarks", ROM0
