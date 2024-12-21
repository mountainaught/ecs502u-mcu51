;================================================
; module  : ECS502U - Microprocessors
; created : 2024/11/20
; creator : ec23528/ETU
; lets all love lain
;================================================

; make sure we've set our data stuffs
RDpin equ 0B3h
WRpin equ 0B2h
A0pin equ 0B5h
A1pin equ 0B4h

org 8000h
KCODE0: db 06h,5Bh,4Fh,71h ; these are our "seven segment display codes"
KCODE1: db 66h,6Dh,7Dh,79h ; it's data telling us what value is what
KCODE2: db 07h,7Fh,67h,5Eh ; later on we'll use a data pointer to check our keypad
KCODE3: db 77H,3Fh,7Ch,58h

org 8100h
Start:
	setb A0pin ; a1 high a0 high
	setb A1pin ; aka "8051/8255 control change mode 2024 free no scam"
	mov a, #81h ; 81h tells us what port assignments we want - consult docus
	mov P1, a ; move our command to the port
	acall write ; send the command

	acall reset
	jmp KLoop

Reset:
	mov R0,#00h ; seg one
	mov R1,#00h ; seg two
	mov R2,#00h ; seg three
	mov R3,#00h ; seg four
	mov R7,#00h ; incoming value

	ret
; ======== main keyboard loop ========
KLoop:
	clr A0PIN ; a0 low a1 high
	setb A1PIN ; aka read mode - we wanna find out if a button is being pressed
	mov P1,#0FFh ; #0FFh - meaning "read all rows/columns"
	acall write ; send read command
	acall read ; read return data

	jnz input_detect ; if the above read has any return data, we want to inspect that
	jmp no_input ; if not, just call display and loop - this is essentially a if-else block
	input_detect: ; i did this cuz i wanted to "call" the check routine instead of jumping to it
		acall keycheck
	no_input: ; else just loop back
		acall display
		jmp kloop
; ======== keycheck: one-by-one column and row checks ========
KeyCheck:
	jb a.0,col0 ; 1,4,7,A
	jb a.1,col1 ; 2,5,8,0
	jb a.2,col2 ; 3,6,9,B
	jb a.3,col3 ; F,E,D,C

	col0:mov b,#0 ; we already have the return value in the accumulator, so
	sjmp rowcheck ; this bit jumps to the column held in the return info
	col1:mov b,#1 ; notes the column in the b accumulator and jumps to
	sjmp rowcheck ; the row checking code
	col2:mov b,#2 ; (this will be useful later for choosing dptr value)
	sjmp rowcheck
	col3:mov b,#3
	sjmp rowcheck

RowCheck:
	clr A0PIN
	setb A1PIN

	; row 0 (1,2,3,F)
	mov dptr, #KCODE0 ; move our first data pointer to the keyboard row 0
	mov P1,#1Fh ; tell the 8255 we wanna read the first row
	acall write
	acall read
	cjne a,#00h,aftercheck ; if we got something, move on to the post-processing

	; row 1 (4,5,6,E)
	mov dptr, #KCODE1 ; more of the same from above
	mov P1,#2Fh
	acall write
	acall read
	cjne a,#00h,aftercheck

	; row 2 (7,8,9,D)
	mov dptr, #KCODE2
	mov P1,#4Fh
	acall write
	acall read 
	cjne a,#00h,aftercheck

	; row 3 (A,0,B,C)
	mov dptr, #KCODE3
	mov P1,#8Fh
	acall write
	acall read
	cjne a,#00h,aftercheck

	ret
; ======== aftercheck: post-check data processing and debouncing ========
AfterCheck:
	acall Display ; refresh out display, this is also the first line of the debounce
	clr A0PIN ; 	a0 low a1 high
	setb A1PIN ; 	aka read mode - we wanna find out if a button is being pressed
	mov P1,#0FFh ; 	we do the 'read everything' routine again
	acall write ; 	the purpose of which is to implement debouncing
	acall read ; 	if the accum is not zero, meaning the user is still pressing a button
	jnz aftercheck ;then we loop back to the beggining of this part, refresh the display and check again

	mov a, b ; else we move the contents of b to a (our previously saved column info)
	movc a,@a+dptr ; since a is now the 'index' of the data in the dptr, we do a+dptr and move that value to the accum
	mov R7, a ; and move it to R7 - incoming data reg

	cjne R7, #71h, noblank ; if the 'F' key is pressed we want to reset the screens, so we check for that here
	acall reset ; call Reset to blank all values
	jmp return ; and jump to the ret instruct
	noblank: ; this is my hodgepodge way of making a if-else block by the way
	acall segshift ; move all the digits to the left
	return:
	ret

SegShift:
	mov a,R2 ; just move the values back and forth between the accumulator and the registers
	mov R3,a ; eventually moving each value to the left
	mov a,R1
	mov R2,a
	mov a,R0
	mov R1,a
	mov a,R7
	mov R0,a

	lcall delay
	ret
; ======== display ========
Display:
	; reset our control pins
	clr a0pin
	clr a1pin

	; --- segment zero (leftmost) ---

	; select, activate and blank out
	setb a0pin ; display select pin
	mov P1, #00001000b ; digit selection byte
	acall write ; write selection to 8255
	clr a0pin

	mov P1, R3 ; choose which segments to light up
	acall write ; write
	acall delay ; delay so the human eye can see the segment light up

	mov P1, #00h ; blank the segment out so it doesn't ghost
	acall write ; write

	; --- segment one ---

	; activate and wait
	setb a0pin
	mov P1, #00000100b
	acall write
	clr a0pin

	mov P1, R2
	acall write
	acall delay

	mov P1, #00h
	acall write

	; --- segment two ---

	setb a0pin
	mov P1, #00000010b
	acall write
	clr a0pin

	mov P1, R1
	acall write
	acall delay

	mov P1, #00h
	acall write

	; --- segment three (rightmost)---

	setb a0pin
	mov P1, #00000001b
	acall write
	clr a0pin

	mov P1, R0
	acall write
	acall delay

	mov P1, #00h
	acall write

	ret
; ======== helper functions ========
read: ; read incoming data from 8255
	clr RDpin ; clear and set - a pulse meaning "send data"
	nop
	mov a, P1 ; read the incoming data into accum
	setb RDpin
	anl a,#0Fh ; mask the first four bits - aka our control stuff
	nop
	ret

write: ; write onto 8255, this could be control bits or commands to read data
	clr  WRpin ; clear and set, our write pulse
	nop
	setb WRpin
	nop
	ret

delay: ; delay func - used here and there
	mov      r5, #05Fh
delayloop:
	djnz     r5, delayloop
	ret
END