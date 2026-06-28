; Check whether any party monster can learn a given TM/HM move.
; Mirrors CheckPartyMove but tests learnability rather than a known move.
;
; Input:
;   d: move ID to check (e.g. CUT, SURF, STRENGTH)
;
; Output:
;   carry clear: at least one party mon can learn the move;
;                wCurPartyMon holds its party index
;   carry set:   no party mon can learn the move
;
; Clobbers: a, bc, hl
CheckPartyCanLearnTMHMMove:
    ld e, 0 ; Current monster
    xor a ; Returned monster (if any)
    ld [wCurPartyMon], a
.loop
    ; Check monster e
    ld c, e
    ld b, 0
    ld hl, wPartySpecies
    add hl, bc
    ld a, [hl]
    ; End of party? Set the carry and return
    scf
    inc a
    ret z ; a was $FF
    dec a
    ret z; a was $00
    ; Skip eggs
    cp EGG
    jr z, .next

    ; Call CanLearnTMHMMove
    ld [wCurPartySpecies], a
    ld a, d
    ld [wPutativeTMHMMove], a
    predef CanLearnTMHMMove
    ld a, c
    and a
    jr nz, .yes

.next
    inc e
    jr .loop

.yes
    ; Save mon to wCurPartyMon
    ld a, e
    ld [wCurPartyMon], a
    xor a ; carry clear = found (xor always clears C)
    ret
    