ResetMapBufferEventFlags::
	xor a
	ld hl, wEventFlags
	ld [hli], a
	ret

ResetBikeFlags::
	xor a
	ld hl, wBikeFlags
	ld [hli], a
	ld [hl], a
	ret

ResetFlashIfOutOfCave::
	ld a, [wPermission]
	cp ROUTE
	jr z, ForceResetFlash
	cp TOWN
	ret nz
ForceResetFlash::
	ld hl, wStatusFlags2
	res 0, [hl]
	ret

GetFlagAddress::
; Get the address and bitmask of bit de in flag array hl.

; inputs:
; de: bit number
; hl: index within bit table

; outputs:
; c: bitmask
; hl: byte address

; clobbers: de

	ld c, 1
	; shift de right by three bits (get the index within memory)
	; at the same time, get the right bit of c set
	srl d
	rr e
	jr nc, .skip_one
	rlc c
.skip_one

	srl d
	rr e
	jr nc, .skip_two
	rlc c
	rlc c
.skip_two

	srl d
	rr e
	jr nc, .skip_three
	swap c
.skip_three
	add hl, de
	ret

CheckEventFlag:
	ld hl, wEventFlags
CheckFlag:
	call GetFlagAddress
	ld a, [hl]
	and c
	ret

SetEventFlag:
	ld hl, wEventFlags
SetFlag:
	call GetFlagAddress
	ld a, [hl]
	or c
	ld [hl], a
	ret

ClearEventFlag:
	ld hl, wEventFlags
ClearFlag:
	call GetFlagAddress
	ld a, c
	cpl
	and [hl]
	ld [hl], a
	ret

; Perform action b on flag c of bitfield [hl].
;
; Input:
;   b:  RESET_FLAG (0), SET_FLAG (1), or CHECK_FLAG (2)
;   c:  0-based bit index (use BigFlagAction for larger arrays)
;   hl: pointer to the bitfield in WRAM
;
; Output (CHECK_FLAG only):
;   a, c: masked byte — 0 if bit clear, nonzero if bit set
;   z:    set if bit is 0 (not present), reset if bit is 1 (present)
;
; Preserves bc, de, hl.
FlagAction::
	push bc
	push de
	push hl
	ld d, 0
	ld e, c
	call BigFlagAction
	pop hl
	pop de
	pop bc

	ldh [hBuffer], a
	ld a, b
	cp CHECK_FLAG
	ret nz
	ldh a, [hBuffer]
	ld c, a
	and a
	ret

EventFlagAction::
	ld hl, wEventFlags
; Perform action b onto flag de of bitfield [hl]
BigFlagAction::
	ld a, b
	cp 1
	jr c, ClearFlag ; 0
	jr z, SetFlag ; 1
.check_flag
	call CheckFlag
	ld c, a
	ret
