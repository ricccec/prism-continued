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
CheckPartyCanLearnTMHMMove::
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


; Check whether the player owns a specific TM/HM.
;
; Input:
;   wCurTMHM: 1-based TM/HM number (MOVE_TMNUM constant)
;   — or —
;   c: 1-based TM/HM number (call _CheckTMHMItem directly)
;
; Output:
;   carry clear: owned
;   carry set:   not owned
CheckTMHMItem::
        ld a, [wCurTMHM]
        ld c, a
_CheckTMHMItem::
        dec c ; FlagAction expects a 0-based bitfield
        ld b, CHECK_FLAG
        ld hl, wTMsHMs
        call FlagAction
        ret nz
        scf ; Set carry flag if not found
        ret