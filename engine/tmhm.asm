; Check whether wCurPartySpecies can learn wPutativeTMHMMove.
;
; inputs:
; wCurPartySpecies: species to check
; wPutativeTMHMMove: move ID to look up
;
; outputs:
; c: nonzero if the species can learn the move, 0 otherwise
; z: set if cannot learn, reset if can learn
CanLearnTMHMMove:
	push de		; FarCopyBytes clobbers de
	call .CanLearnTMHMMove
	pop de
	ret

.CanLearnTMHMMove:
	; Point hl to wCurPartySpecies' learnset
	ld a, [wCurPartySpecies]
	dec a		; species IDs are 1-indexed
	ld hl, TMHMLearnsets
	ld bc, 13	; Each species' learnset is 13 bytes
	rst AddNTimes	

	; Copy the 13-byte learnset bitfield into WRAM at wCurBaseData
	ld a, BANK(TMHMLearnsets)
	ld bc, 13
	ld de, wCurBaseData
	call FarCopyBytes

	ld hl, wCurBaseData
	push hl		; FIXME: this is redundant, we could just load
				; wCurBaseData into hl at .found

	; Scan TMHMMoves to find the 0-based bit index (in c) of wPutativeTMHMMove
	ld a, [wPutativeTMHMMove]
	ld b, a
	ld c, 0
	ld hl, TMHMMoves
.loop
	ld a, [hli]
	and a		; null terminator
	jr z, .end
	cp b
	jr z, .found
	inc c
	jr .loop

.found
	; Check if bit c of the learnset bitfield is set
	pop hl
	ld b, CHECK_FLAG
	predef_jump FlagAction

.end
	pop hl		; balance the push above; value unused
	ld c, 0
	ret

GetTMHMMove::
	ld a, [wCurTMHM]
	and $7f
	dec a
	ld hl, TMHMMoves
	ld b, 0
	ld c, a
	add hl, bc
	ld a, [hl]
	ld [wd265], a
	ret

INCLUDE "data/tmmoves.asm"
