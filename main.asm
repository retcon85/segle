#define RAMTOP 		$dff8
#define RAMSTART 	$c001				; allowing 1 byte for port $3e backup
#define	WORD_LEN 	5				; 5 letters in a word
#define	N_GUESSES 	6				; 6 guesses per game
#define VDP_CMD		$bf
#define VDP_DATA	$be
#define JSPORT_A	$dc
#define DELAY_16_MS	1
#define MAX_LETTER	26				; defines when letter scrolling wraps, i.e. from Z to A in English alphabet
#define PALETTE_SIZE	32

; define variables in RAM

defvars RAMSTART
{
	draw_result	ds.b	1			; counts down number of letters in result which need drawing during animation
	buffer_pos	ds.b	1			; the position of the user in the current guess buffer (e.g. between 0 and 4)
	row_pos		ds.b	1			; the position of the active character, across all rows (e.g. between 0 and 29)
	answer_ptr	ds.b	2			; pointer to the address of the chosen answer for this game
	buffer		ds.b	WORD_LEN		; the (WORD_LEN) character buffer of the current guess line
	delay		ds.b	1			; a configurable holdoff delay e.g. after button presses, during animation
	correct_answers ds.b	1			; the count of the number of correct (green) letters in the last guess
	END_VARS	ds.b	0			; just a helpful label
}

extern vdp_tiles					; the start of the tile definitions for the game letters
extern vdp_toast_tiles					; the start of the tile definitions for the toast messages on win / lose
extern vdp_toast_tiles_end
extern answers						; the list of possible answers (uppercase ASCII)

org 0							; start at the beginning :)

; basic system init
		di
		im 1
		ld sp, RAMTOP
		jp init

; VDP interrupt handler
align $0038
		jr frame_interrupt

; pause button handler (does nothing in this game)
align $0066
		retn

; main handler routine - called once every frame (1/60 seconds)
frame_interrupt:
		push af
		push bc
		push de
		push hl

		in a, (VDP_CMD)				; tell VDP to cancel interrupt

		; check for end of game
		ld a, (draw_result)
		or a
		jr nz, _handle_delay			; game can only end if we've finished drawing the result
		ld a, (correct_answers)
		cp WORD_LEN				; correct_answers == 5 means a win
		jr nz, _check_loss
		ld a, (row_pos)				; calculate toast message from number of guesses
		ld b, 0
		ld d, 0
_get_msg:
		inc b
		sub WORD_LEN
		jr nz, _get_msg				; keep subtracting 5 until we have the number of rows in reg b
		ld hl, toast_messages
		dec b
_next_msg:
		ld e, (hl)				; read number of characters in this message into reg e
		jr z, _end_game				; when b is zero, we have found our message, finally display it and quit
		inc e
		add hl, de				; otherwise, skip over this word
		dec b					; try the next one
		jr _next_msg

_check_loss:
		ld a, (row_pos)
		cp N_GUESSES * WORD_LEN			; if we have used all the guesses, it's a loss
		jr nz, _handle_delay
		ld e, WORD_LEN				; there are always 5 letters in the answer toast
		ld hl, (answer_ptr)			; point to the answer
		dec hl

_end_game:
		ld b, e
		inc hl
		ld a, (correct_answers)
		or a
		ld d, 5					; display the toast on row 5 if we incredibly happened to guess the word first time
		jr nz, _end_game_c1
		ld d, 0  				; under all other circumstances, display the toast on row 0
_end_game_c1:
		call display_toast

		xor a					; cancel delay and quit handler
		jp _ret					; !TODO: wanted to di and halt here instead, but it didn't work - find out why

_handle_delay:
		; if there is a delay, just decrement it and return
		ld a, (delay)
		or a
		jr z, _no_delay
		dec a
		jp _ret					; quit handler - delay will be saved later on exit

_no_delay:
		; draw the result animation if we are in the draw_result cycle
		ld a, (draw_result)
		or a
		jr z, _check_input
		ld c, a
		ld hl, buffer
		ld a, WORD_LEN
		sub c
		ld e, a
		ld d, 0
		add hl, de
		ld d, (hl)				; reg d now contains the correct buffer entry for this interrupt
		ld a, d
		and $c0
		jr nz, _styled
		set 6, d				; adjust the style to be incorrect if not correct or partially correct
_styled:
		ld a, (row_pos)
		sub c					; reg a now contains the correct draw position for this interrupt
		call load_tile_set
		ld a, c
		dec a
		ld (draw_result), a			; update draw result entry
		ld a, DELAY_16_MS * 20
		jp _ret

		; check to see if any joypad buttons are pressed
_check_input:
		ld hl, (buffer_pos)
		ld bc, hl
		ld de, buffer
		ld h, 0
		add hl, de
		ld a, (hl)
		ld d, a					; reg d = current character in buffer

		in a, (JSPORT_A)
		srl a
		jr nc, _up
		srl a
		jr nc, _down
		srl a
		jr nc, _left
		srl a
		jr nc, _right
		srl a
		jr nc, _btn1
		srl a
		jr nc, _btn2
		xor a				        ; don't set a delay if no button is pressed
		jp _ret
_up:
		ld a, d
		cp MAX_LETTER
		jr nz, _up_c1
		xor a				        ; wrap around from e.g. Z to A
_up_c1:
		inc a					; pressing up moves to next character in alphabet
		and $1f
		ld (hl), a				; save to buffer
		ld d, a
		ld a, b
		call load_tile_set
		ld a, DELAY_16_MS * 5			; 30ms delay is enough to allow fine user control
		jp _ret
_down:
		ld a, 1
		cp d
		ld a, d
		jr c, _dn_c1
		ld a, MAX_LETTER+1
_dn_c1:
		dec a					; pressing down moves to previous character in alphabet
		and $1f
		ld (hl), a				; save to buffer
		ld d, a
		ld a, b
		call load_tile_set
		ld a, DELAY_16_MS * 5			; 30ms delay is enough to allow fine user control
		jp _ret
_left:
_btn1:							; button 1 does the same thing as pressing left (delete character)
		xor a
		cp c
		jr z, _ret				; if we are already at the start of the buffer, do nothing (return)
		ld (hl), a				; otherwise, set current character to blank and save to buffer
		ld d, a
		ld a, b
		call load_tile_set			; update screen
		dec b					; move the cursors back one character
		dec c
		ld hl, bc
		ld (buffer_pos), hl			; update buffer_pos and row_pos 
		ld a, DELAY_16_MS * 15			; extra delay on delete so it's less likely we accidentally delete too far
		jr _ret
_right:
		ld a, b
		call load_tile_set			; !TODO: fix this workaround - repeats first character of last buffer if right pressed with nothing selected
		ld a, d
		xor a
		cp d
		jr z, _ret				; if we haven't yet chosen a character for the current cell, do nothing (return)
		ld a, c
		cp WORD_LEN-1
		jr z, _ret				; if we are already at the end of the buffer, do nothing (return)
		ld d, 1
		ld a, d
		inc hl
		ld (hl), a
		inc b
		inc c
		ld hl, bc
		ld (buffer_pos), hl			; update buffer_pos and row_pos 
		ld a, b
		call load_tile_set
		ld a, DELAY_16_MS * 25			; extra delay on next character as it's annoying to have to delete when it adds too many letters
		jr _ret
_btn2:
		; submit a guess - calculate how correct it is!
		ld a, c
		cp WORD_LEN-1
		jr nz, _ret				; can't submit guess unles buffer is full

		; !TODO: check word is valid here!

		ld c, 0
		inc b
		ld hl, bc
		ld (buffer_pos), hl			; save buffer & row pointers for next row
		ld b, 0					; reg b contains number of correct_answers
		ld de, (answer_ptr)
		ld hl, buffer
		ld c, WORD_LEN
_chk_correct:
		ld a, (de)				; DE contains address of answer
		sub 'A'-1				; convert from ASCII
		cp (hl)					; compare with corresponding letter from buffer
		jr nz, _chk_partial
		or $c0 					; apply styling for correct answer
		ld (hl), a				; save back into buffer
		inc b					; correct_answers
		jr _incorrect
_chk_partial:
		push bc					; save the bc and hl registers because we need them
		push hl
		ld hl, buffer				; scan from the start of the buffer
		ld bc, WORD_LEN
_chk_cont:
		cpir					; find a matching letter in the buffer
		jr nz, _chk_done			; if none found, restore registers and finish
		push af
		dec hl
		ld a, (hl)				; if we found one, load the character
		or $80					; apply styling for partially correct answer
		ld (hl), a				; save back into buffer
		xor a
		cp c					; check whether we still have more letters to test
		pop af
		jr nz, _chk_cont			; loop if letters still to test
_chk_done:
		pop hl
		pop bc
_incorrect:
		inc hl					; move to next letter in answer
		inc de					; move to next letter in buffer
		dec c
		jr nz, _chk_correct
_queue_redraw:
		ld hl, correct_answers
		ld (hl), b				; save correct_answers
		ld a, WORD_LEN
		ld (draw_result), a			; set draw_result flag to trigger result "animation"
		xor a

_ret:
		ld (delay), a
		pop hl
		pop de
		pop bc
		pop af
		ei
		reti					; from interrupt handler

; init - called once at beginning of game
init:
		; initialize variables in ram to zero
		ld hl, RAMSTART
		ld b, END_VARS - RAMSTART
_init_l0:
		ld (hl), 0
		inc hl
		djnz _init_l0

		ld hl, answers				; set answer pointer to the first answer, will get randomized later
		ld (answer_ptr), hl

		; initialize all vdp registers - copy from bytes in vdp_init_reg
		xor a
		ld hl, vdp_init_reg
		ld c, VDP_CMD
		ld b, 11
		ld d, $80
_init_l1:
		outi
		nop
		out (c), d
		inc d
		cp b
		jr nz, _init_l1

		; copy palette data
		out (VDP_CMD), a
		ld b, $c0
		out (c), b
		ld c, VDP_DATA
		ld b, PALETTE_SIZE
		otir

		; load tiles
		; organizing as 30 "sets" of 8 tiles, one set per letter on the grid
		; this means we only need max 240 tiles (of 448) leaving plenty of spare for the toast message tiles
		; my original idea was to have 4 sets of 108 (26 * 4 + 4 border, blank, etc.) - one set for each "state" of the grid letters
		; but this would need 432 tiles, leaving none spare and would also be hard to organize
		; the major disadvantage of the technique I'm using is that updating tile sets means shifting a lot of bytes (8 * 32 * 5 = 1280 per line)
		; and too much to update in a single VDP VBLANK frame
		; luckily, we need a per-letter animation effect anyway, so we can update one letter in a set at a time no problems
		; I would like to come back to this and possibly use a split palette to cut the tile set down instead
		out (VDP_CMD), a
		ld a, $40
		out (VDP_CMD), a
		xor a
		ld d, WORD_LEN * N_GUESSES 		; d = tile set counter - 5 * 6 = 30 sets of tiles to set up
_init_l2:
		ld hl, vdp_tiles
		ld b, 32 * 3 				; tile 0 = blank, tile 1 = unguessed corner, tile 2 = unguessed horizontal
		otir
		ld b, 32
		ld hl, vdp_tiles
		add hl, 32 * 65 			; tile 65 = unguessed vertical 
		otir
		ld b, 32 * 2  				; tiles 3 & 4, both blank
		ld hl, vdp_tiles
		add hl, 32 * 3
		otir
		ld b, 32 * 2  				; tiles 3 & 4, both blank
		ld hl, vdp_tiles
		add hl, 32 * 3
		otir
		dec d
		jr nz,_init_l2

		; initialize screen map so that each of the characters in the game grid maps to its own tile set as per above
		; this is a pretty tedious thing to do. I could probably have written it better
		xor a
		out (VDP_CMD), a
		ld a, $78
		out (VDP_CMD), a
		ld h, N_GUESSES
		ld l, 1
_init_l3:
		call draw_border			; 6 blank tiles on left of each row to center screen
		ld b, WORD_LEN				; reg b = which letter in each row
_init_l5:
		; top left corner
		out (c), l
		xor a
		out (VDP_DATA), a
		; top edge x 2
		inc l
		out (c), l
		nop
		out (VDP_DATA), a
		nop
		out (c), l
		nop
		out (VDP_DATA), a
		; top right corner
		dec l
		out (c), l
		ld a, 2
		out (VDP_DATA), a
		ld a, l
		add a, 8
		ld l, a
		djnz _init_l5
		; right border of current row
		call draw_border
		; left border of next row
		call draw_border
		ld b, WORD_LEN
		sub 38					; carriage return :)
		ld l, a
_init_l6:
		; left edge
		out (c), l
		xor a
		out (VDP_DATA), a
		inc l
		; character top left
		out (c), l
		nop
		out (VDP_DATA), a
		inc l
		; character top right
		out (c), l
		dec l
		out (VDP_DATA), a
		dec l
		; right edge
		out (c), l
		ld a, 2
		out (VDP_DATA), a
		ld a, l
		add a, 8
		ld l, a
		djnz _init_l6
		; right border of current row
		call draw_border
		; left border of current row
		call draw_border
		ld b, WORD_LEN
		sub 40					; carriage return :)
		ld l, a
_init_l7:
		; left edge
		out (c), l
		xor a
		out (VDP_DATA), a
		inc l
		inc l
		inc l
		; character bottom left
		out (c), l
		nop
		out (VDP_DATA), a
		inc l
		; character bottom right
		out (c), l
		dec l
		out (VDP_DATA), a
		dec l
		dec l
		dec l
		; right edge
		out (c), l
		ld a, 2
		out (VDP_DATA), a
		ld a, l
		add a, 8
		ld l, a
		djnz _init_l7
		; right border of current row
		call draw_border
		; left border of current row
		call draw_border
		ld b, WORD_LEN
		sub 42					; carriage return :)
		ld l, a
_init_l8:
		; bottom left corner
		out (c), l
		ld a, 4
		out (VDP_DATA), a
		inc l
		; bottom edge x2
		out (c), l
		nop
		out (VDP_DATA), a
		nop
		out (c), l
		nop
		out (VDP_DATA), a
		dec l
		; bottom right corner
		out (c), l
		ld a, 6
		out (VDP_DATA), a
		ld a, l
		add a, 8
		ld l, a
		djnz _init_l8
		call draw_border
		
		dec h
		jp nz, _init_l3

		; load toast tiles
		; 32 * 58 tiles = 1856 so need to loop 8 times as otir can only do 256 at a time
		xor a
		out (VDP_CMD), a
		ld a, $60
		out (VDP_CMD), a
		
		ld hl, vdp_toast_tiles
		ld de, vdp_toast_tiles_end - vdp_toast_tiles
		ld b, e
_init_l9:
		otir
		ld a, d
		or a
		jr z, _init_c1
		dec d
		jr _init_l9

		; finished loading VDP data - can turn display on and start interrupts
_init_c1:
		call display_on

		; randomize - sits in a tight loop cycling through possible answers until the user starts guessing
		ld hl, (answer_ptr)
		ld de, WORD_LEN
		ei					; need to enable interrupts before we start randomizing
_randomize:
		ld a, (hl)				; read the first letter at answer_ptr
		add hl, de				; move to the next word
		cp $ff
		jr nz, _randomize_c1
		ld hl, answers				; if it's the special stop character $ff then start from the beginning

_randomize_c1:
		ld a, (buffer)				; check to see if there is anything in the guess buffer
		or a
		jr z, _randomize			; keep generating "random" answers until the player has started filling the buffer
		ld (answer_ptr), hl			; store the random answer pointer permanently

; wait
;   - just halts and loops in case anything returns out of the halt
wait:
		halt
		jr wait

; display_on
;   - does exactly what it says on the tin
display_on:
		push af
		ld a, (vdp_init_reg + 1)
		or $40
		out (VDP_CMD), a
		ld a, $81
		out (VDP_CMD), a
		pop af
		ret

; display_off
;   - does exactly what it says on the tin
display_off:
		push af
		ld a, (vdp_init_reg + 1)
		and ~$40
		out (VDP_CMD), a
		ld a, $81
		out (VDP_CMD), a
		pop af
		ret

; draw_border
;   - small utility to send 6 blank tiles to the screen
; modifies
;   - b	
draw_border:
		push af
		ld b, 6 ; BORDER
		ld a, 0
_draw_border_l1:
		out (VDP_DATA), a
		nop
		out (VDP_DATA), a
		djnz _draw_border_l1
		pop af
		ret

; load_tile_set
;   - replaces VDP tile definitions in order to render guesses to the screen
; args:
;   - reg a = guess number 0 -> 30
;   - reg d = bits 0:4 = character code ('A' = 1, etc.); bits 7:6 = style (00 = unguessed, 01 = incorrect, 10 = partial, 11 = correct)
; modifies:
;   -
load_tile_set:	
		push af
		push bc
		push de
		push hl
		ex af, af'
		xor a
		out (VDP_CMD), a
		ex af, af'
		or $40
		out (VDP_CMD), a
		
		ld c, VDP_DATA

		; shift de into position
		sla d
		inc d
		inc d
		inc d
		ld e, 0
		rr d
		rr e
		srl d
		rr e
		srl d
		rr e

		; load hl to character code 0, retaining style bits
		ld a, d
		and $30
		ld h, a
		ld l, 0
		add hl, vdp_tiles
		ld b, 32 * 3 ; first three tiles in set
		otir
		add hl, 62 * 32 ; move to character 65 (already at 3 + 62 = 65)
		ld b, 32
		otir
		; now print the actual characters
		ld hl, de
		add hl, vdp_tiles
		ld b, 32 * 2
		otir
		add hl, 62 * 32; move to bottom row
		ld b, 32 * 2
		otir
		pop hl
		pop de
		pop bc
		pop af

		ret

; display_toast
;   - displays a toast message on the screen
; args:
;  	- reg b  = number of characters in message
;   - reg d  = row of screen to start message on
;   - reg hl = pointer to message characters to display
; modifies:
;   - a, b, c, d, e, h, l
display_toast:
		call display_off 			; !TODO: figure out why it doesn't work without this
		; calculate starting point
		ld c, VDP_CMD
		ld e, 0
		srl d
		rr e
		srl d
		rr e
		ld a, $c0
		out (c), e
		ld a, d
		add $78
		out (VDP_CMD), a

		; b = counter
		; c = message width
		; d = row number
		; e = margin width

		; calculate margin width
		ld c, b
		ld a, 30
		sub b					; total margin = 32 screen width - 2 border tiles - message length
		ld e, a					; store margin width in reg e

		ld d, 5					; toast is 5 lines high
_toast_line:
		; left margin
		ld b, e
		srl b					; divide margin width by two to get left margin width
_toast_lmargin:
		ld a, $00
		out (VDP_DATA), a
		ld a, $19
		out (VDP_DATA), a
		djnz _toast_lmargin

		; either a corner or edge piece
		ld a, d
		dec a
		and $03					; if row is 1 or 5, draw the corner piece
		ld a, $01
		jr z, _toast_c1
		ld a, $03				; otherwise draw the edge piece
_toast_c1:
		out (VDP_DATA), a

		ld a, d
		cp 1
		ld a, $0d				; if row is 1, flip vertically
		jr z, _toast_c2
		ld a, $09				; otherwise don't flip
_toast_c2:
		out (VDP_DATA), a

		; top edge, the message, or padding
		ld b, c					; number of characters in message
		ld a, d
		cp 3					; if row is 3, draw the message
		jr z, _toast_message
		dec a
		and $03
		ld a, $02				; if row is 1 or 5, draw the top or bottom edge
		jr z, _toast_c3
		ld a, $04				; else draw some padding
_toast_c3:
		ex af, af'
		ld a, d
		cp 1
		ld a, $0d				; if row is 1, flip vertically
		jr z, _toast_middle
		ld a, $09				; otherwise don't flip
_toast_middle:
		ex af, af'
		out (VDP_DATA), a
		ex af, af'
		out (VDP_DATA), a
		djnz _toast_middle
		jr _toast_c4

_toast_message:
		ld a, (hl)
		sub a, 'A'-5				; convert from ASCII
		out (VDP_DATA), a
		ld a, $09
		out (VDP_DATA), a
		inc hl
		djnz _toast_message
_toast_c4:
		; either a corner or edge piece
		ld a, d
		dec a
		and $03					; if row is 1 or 5, draw the corner piece
		ld a, $01
		jr z, _toast_c5
		ld a, $03				; otherwise draw the edge piece
_toast_c5:
		out (VDP_DATA), a

		ld a, d
		cp 1
		ld a, $0f				; if row is 1, flip vertically
		jr z, _toast_c6
		ld a, $0b				; otherwise don't flip
_toast_c6:
		out (VDP_DATA), a

		; right margin
		ld b, e
		srl b					; divide margin width by two to get left margin width
		ld a, e
		sub b					; subtract left margin from total margin to get right margin width
		ld b, a
_toast_rmargin:
		ld a, $00
		out (VDP_DATA), a
		ld a, $09
		out (VDP_DATA), a
		djnz _toast_rmargin

		dec d
		jr nz, _toast_line
		call display_on 			; !TODO: figure out why it doesn't work without this
		ret

toast_messages:
		db 6,  "Genius"
		db 11, "Magnificent"
		db 10, "Impressive"
		db 8,  "Splendid"
		db 5,  "Great"
		db 4,  "Phew"

vdp_init_reg:
		; vdp registers
		db $06,$a0,$ff,$ff,$ff,$ff,$ff,$04,$00,$00,$ff

		; IMPORTANT! palette & tile definitions follow on directly after vdp_init_reg block
