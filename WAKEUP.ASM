;-------------------------------------------------------
; WAKEUP.ASM -- OS/2 Detachable Alarm Program
; Copyright (c) 1988, Ziff Communications Co.
; PC Magazine * Charles Petzold
;-------------------------------------------------------

		.286C
		DOSSEG
		.MODEL	SMALL
		.STACK	0200h

	; ---------------------------------------------
	;  OS/2 External Functions and Data Structures
	; ---------------------------------------------

		EXTRN	DosBeep:FAR, DosExit:FAR, DosGetDateTime:FAR		EXTRN	DosSleep:FAR, DosWrite:FAR, KbdCharIn:FAR
		EXTRN	KbdFlushBuffer:FAR, VioEndPopUp:FAR, VioPopUp:FAR
		EXTRN	VioSetCurPos:FAR, VioWrtNAttr:FAR, VioWrtTTY:FAR, 

DateTimeStruc	STRUC
			hour		db	?
			minutes		db	?
			seconds		db	?
			hundreths	db	?
			day		db	?
			month		db	?
			year		dw	?
			timezone	dw	?
			day_of_week	db	?
DateTimeStruc	ENDS

KeyDataStruc	STRUC
			char_code	db	?
			scan_code	db	?
			status		db	?
			nls_shift	db	?
			shift_state	dw	?
			time		dd	?
KeyDataStruc	ENDS
					; --------------------------
		.DATA			;  Initialized Data Segment
					; --------------------------

SyntaxMsg	db	13, 10,     "Syntax: DETACH WAKEUP hour:minute"
		db	13, 10, 10, 9,      "Use 24-hour time format."
		db	13, 10, 10, "(c) 1988, Ziff Communications Co."
		db      13, 10,     "PC Magazine ",254, "Charles Petzold"
		db	13, 10
SyntaxMsgLen	equ	$ - SyntaxMsg
		db	10,         "Press any key to return to OS/2..."
SyntaxMsgLen2	equ	$ - SyntaxMsg

WakeupMsg	db	"WAKE UP!  WAKE UP!  WAKE UP!"
WakeupMsgLen	equ	$ - WakeupMsg

Delimiters	db	9, " ,;="
PopupFlag	dw	1
Attribute	db	4Fh, 74h
					; ----------------------------
		.DATA?			;  Uninitialized Data Segment
					; ----------------------------
BytesWritten	dw	?
DateTime	DateTimeStruc <>
KeyData		KeyDataStruc <>
					; --------------
		.CODE			;  Code Segment
					; --------------
		ASSUME	ES:DGROUP

; ---------------------------------------------
;  Parse command line to find the wake-up time
; ---------------------------------------------

Entry:		Push	DS			; Data segment selector
		Pop	ES			; Transfer it to ES
		Mov	DS, AX			; DS = Environment selector
		Mov	SI, BX			; SI = Start of command line
		Sub	AH, AH			; A little preparation 

						; Skip name and delimiters
						; ------------------------

SkipProgName:	Lodsb				; Pull a command line byte
		Or	AL, AL			; Check if it's zero
		Jnz	SkipProgName		; If not, continue

SkipDelims:	Lodsb				; Get another byte
		Or	AL, AL			; See if it's zero
		Jz	ParamError		; If so, that's no good

		Mov	DI, Offset Delimiters	; All possible delimiters
		Mov	CX, 5			; Five of them
		Repnz	Scasb			; Scan for a match
		Jz	SkipDelims		; If match, try another byte

						; Calculate Hour
						; --------------

		Call	NumberTrans		; Translate ASCII byte

		Mov	DX, AX			; Save first 'hour' byte in DL

		Lodsb				; Get second 'hour' byte
		Cmp	AL, ':'			; See if it'a a colon
		Jz	GotHour			; If so, hour is finished

		Call	NumberTrans		; If not, translate it

		IMul	DX, 10			; Multiply first byte by 10
		Add	DL, AL			; Add the second byte
		Cmp	DL, 24			; Check if hour is 24 or above
		Jae	ParamError		; What clock do you use? 

		Lodsb				; Get next byte
		Cmp	AL, ':'			; Should be colon
		Jnz	ParamError		; If not, it's an error

GotHour:	IMul	DX, 60			; DX has minutes since midnight

						; Calculate Minutes
						; -----------------

		Lodsb				; First 'minutes' byte
		Call	NumberTrans		; Translate it

		IMul	AX, 10			; Multiply by 10
		Mov	AH, AL			; And save in AH

		Lodsb				; Second 'minutes' byte
		Call	NumberTrans		; Translate it

		Add	AL, AH			; Add the two
		Cmp	AL, 60			; Check if minutes > 60
		Jae	ParamError		; Another bizarre clock

		Sub	AH, AH			; Zero out AH
		Add	DX, AX			; Parameter time in minutes

		Jmp	Short GetCurrentTime	; All done with parsing

; -----------------------------------------------------
;  Display 'syntax' message if an error is encountered
; -----------------------------------------------------

ParamError:	Push	ES			; Restore DS to
		Pop	DS			;   data segment

		Mov	CX, SyntaxMsgLen	; Length of text

WriteSyntaxMsg:	Push	1			; Handle is standard error
		Push	DS			; Segment of text
		Push	Offset SyntaxMsg	; Offset of text
		Push	CX			; Length of text
		Push	DS			; Segment of bytes written
		Push	Offset BytesWritten	; Offset of bytes written
		Call	DosWrite		; Write the error message

		Cmp	CX, SyntaxMsgLen2	; Check if second time through
		Jz	EndPopup		; If so, wait for keystroke

		Or	AX, AX			; If no error, simply exit
		Jz	ErrorExit

		Push	DS			; Segment of PopupFlag
		Push	Offset PopupFlag	; Offset of PopupFlag
		Push	0			; Video handle always zero
		Call	VioPopUp		; Popup on screen

		Mov	CX, SyntaxMsgLen2	; Text length for popup version
		Jmp	WriteSyntaxMsg		; Go to it

EndPopup:	Push	DS			; Segment of KeyData struc
		Push	Offset KeyData		; Offset of KeyData struc
		Push	0			; Wait for keystroke
		Push	0			; Keyboard handle
		Call	KbdCharIn		; Fetch a key

		Push	0			; Video handle
		Call	VioEndPopUp		; End the popup

ErrorExit:	Push	1			; Terminate all threads
		Push	1			; Return error code of 1
		Call	DosExit			; And exit
; ---------------------------------------------------------------------
;  NumberTrans Subroutine -- Translates ASCII to Hex (CY set if error)
; ---------------------------------------------------------------------	

NumberTrans:	Sub	AL, '0'			; ASCII to hex
		Jc	ParamError		; Error if under 0

		Cmp	AL, 9			; Also error if over 9
		Ja	ParamError

BadNumberTrans:	Ret

; ---------------------------------------------------------
;  Get current time, calculate difference, and go to sleep
; ---------------------------------------------------------

GetCurrentTime:	Push	ES			; Restore DS to data segment
		Pop	DS 

		Push	DS			; Push segment address
		Push	Offset DateTime		; Push offset of structure
		Call	DosGetDateTime		; Get current date and time

		Mov	AL, DateTime.hour	; AL is current hour
		Sub	AH, AH			; Zero out top byte
		IMul	AX, 60			; AX is minutes since midnight
		Add	AL, DateTime.minutes	; Add the current minutes
		Adc	AH, 0			; And carry into top byte

		Xchg	AX, DX			; Subtract parameter time
		Sub	AX, DX			;   from current time
		Jnc	DifferenceOK		; OK if both after midnight

		Add	AX, 24 * 60		; Otherwise add whole day

DifferenceOK:	Mov	DX, 60 * 1000		; Milliseconds in 1 minute
		Mul	DX			; DX:AX = interval in msec

		Push	DX			; Push high word
		Push	AX			; Push low word
		Call	DosSleep		; And take a long long nap

; -----------------------------------------------------
;  On return from DosSleep, start beeping and flashing
; -----------------------------------------------------

		Push	DS			; Segment of flag
		Push	Offset PopupFlag	; Offset of flag
		Push	0			; Video handle always 0
		Call	VioPopUp		; Pop up!

		Mov	AX, 80			; 80 columns across screen
		Sub	AX, WakeupMsgLen	; Less the length of message		Shr	AX, 1			; Divide by two for margin

		Push	12			; Row (near the center)
		Push	AX			; Column to center text
		Push	0			; Video handle
		Call	VioSetCurPos		; Set the cursor
		
		Push	DS			; Segment of message
		Push	Offset WakeupMsg	; Offset of message
		Push	WakeupMsgLen		; Length of message
		Push	0			; Darn video handle again
		Call	VioWrtTTY		; Write it out

		Push	0			; Flush keyboard buffer
		Call	KbdFlushBuffer		;   in case user is typing

FlasherLoop:	Mov	AX, 0			; Indicates 1st attribute
		Mov	BX, 512			; One alternating tone
		Mov	DX, 1024		; Second alternating tone
		Call	RingBell		; Start it going

		Mov	AX, 1			; Second attribute
		Mov	BX, 1024		; One alternating tone
		Mov	DX, 2048		; Second alternating tone
		Call	RingBell		; Do it again

		Push	DS			; Segment of KeyData struc
		Push	Offset KeyData		; Offset of KeyData struc
		Push	1			; Do not wait for keystroke
		Push	0			; Keyboard handle
		Call	KbdCharIn		; Fetch a key

		Mov	AL, KeyData.char_code	; Check if character and scn
		Or	AL, KeyData.scan_code	;   code are both zero
		Jz	FlasherLoop		; If so, no key, so continue
		
		Push	0			; Video handle
		Call	VioEndPopUp		; End the popup

		Push	1			; Terminate normally
		Push	0			; With return code for success
		Call	DosExit

; ---------------------------------------------------------------------
;  RingBell Subroutine -- Sets Attribute from AX, Beeps with BX and DX
; ---------------------------------------------------------------------

RingBell:	Add	AX, Offset Attribute	; Attribute for screen

		Push	DS			; Segment of attribute
		Push	AX			; Offset of attribute
		Push	25 * 80			; Number of attributes
		Push	0			; Starting row
		Push	0			; Starting column		Push	0			; Video handle
		Call	VioWrtNAttr		; Write the attribute

		Mov	CX, 10			; Do beeps ten times

RingBell1:	Push	BX			; Frequency
		Push	50			; Duration
		Call	DosBeep			; Beep

		Push	DX			; Frequency 
		Push	50			; Duration
		Call	DosBeep			; Beep

		Loop	RingBell1		; Loop around
		Ret

		END	Entry
