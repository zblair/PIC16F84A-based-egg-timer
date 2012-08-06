; ******************************************************
; * The Big Beepin' Timer                              *
; * ---------------------                              *
; *                                                    *
; * May 16 2006                                        *
; * Copyright (c) Zachary Blair                        *
; *                                                    *
; * This is the source code to a timer I designed      *
; * that contained a Microchip PIC 16F84A              *
; * microcontroller.                                   *
; *                                                    *
; * The mcu is clocked by a 32.768 kHz crystal, and    *
; * it drives three seven segment displays using PORT  *
; * B pins 7-1 and the first three pins in PORT A.     *
; * It also drives a buzzer using PORT A bit 3         *
; * (i.e. the 4th bit on port A). The MCU also has a   *
; * push button attached to PORT B pin 0 that acts as  *
; * a start or reset button to the timer. The button   *
; * shows a logic '1' on RB0 when it is not pressed,   *
; * a logic '0' when it is pressed.                    *
; *                                                    *
; * Basically, when the button is pressed, the timer   *
; * starts counting down from 3 minutes, and it shows  *
; * the current time on the three seven-segment        *
; * displays. At any point, pressing the button again  *
; * will reset the timer to 3 minutes and restart the  *
; * countdown. When the timer reaches zero, it         *
; * activates the buzzer for 1 second, and then the    *
; * buzzer and all of the displays turn off and the    *
; * device switches to its low-power mode, where it    *
; * consumes very little power (it should last for     *
; * months on low-power mode). When the user again     *
; * presses the button, the device is awakened and is  *
; * reset to 3 minutes, and the cycle begins again.    *
; ******************************************************

	include "p16F84a.inc"

; We are using _LP_OXC because we are using a 32.768 kHz crystal
	__config _CP_OFF & _WDT_OFF & _LP_OSC & _PWRTE_ON 

; ******************************************************
; * Variable declarations                              *
; ******************************************************
	cblock 20h
		_work:1, _status:1,	minutes:1, secondsH:1
		secondsL:1, delay_count:1, timeout:1
	endc

; ******************************************************
; * Macro and constant declarations                    *
; ******************************************************

SetTimeTo3Min macro 	; Set time to 3 min 
	movlw d'3'
	movwf minutes
	clrf secondsH
	clrf secondsL
	; Turn off the zero indicator (PORTA bit 3)
	bcf PORTA, 3
	endm

TIMEOUT_SECONDS	equ	d'2'	; Sound the beeper for only 1 second

; ******************************************************
; * Reset and Interrupt vectors                        *
; ******************************************************

	org 0		; Reset vector
	goto MAIN

	org 4		; Interrupt vector
	goto ISR

; ******************************************************
; * The main section is called on startup and reset.   *
; * It performs initialization, and then enters the    *
; * main loop, where it continually refreshes the      *
; * seven segment displays.                            *
; ******************************************************
MAIN
	; Initialize
	clrf PORTA			; Start with all displays off.

	bsf STATUS, RP0		; Go to Bank 1 for OPTION_REG.
	movlw b'00000100'	; Assign prescaler to TMR0,
	movwf OPTION_REG ^ 0x080	; ratio 1:32, internal clock
	clrf TRISA ^ 0x080			; Set all port A pins to outputs
	movlw b'00000001'
	movwf TRISB ^ 0x080	; Set RB0 as input, and and RB1-RB7 an output
	bcf STATUS, RP0		; Switch back to Bank 0

	SetTimeTo3Min		; Initially, start at 3 minutes
	movlw TIMEOUT_SECONDS	; Set the sleep timeout
	movwf timeout

	bsf INTCON,T0IE		; Enable TMR0 interrupt
	bsf INTCON,INTE		; Enable INTE interrupt
						; on the rising edge (default)

	clrf TMR0			; Set TMR0 to zero
	bsf INTCON,GIE		; Enable interrupts

	; When the batteries are first inserted, do not have the
	; screen display anything. Wait for the user to press the
	; big red button!
	sleep
	
	; Loop forever, refreshing the display
	; at a rate dependant on the Delay
	; subroutine.
MAIN_LOOP
	; If RB0 is low, set t=3min
	; and set TMR0 to zero
	btfsc PORTB,0
	goto BUTTON_UP
	SetTimeTo3Min
	clrf TMR0	

BUTTON_UP
	movfw secondsL		
	call BinaryToSevenSegment 
	movwf PORTB			; Put the rightmost digit on B


	bsf PORTA, 0		; Turn on only the rightmost display
	call Delay			; Wait
	bcf PORTA, 0		; Turn off the rightmost display

	movfw secondsH		
	call BinaryToSevenSegment
	movwf PORTB			; Put the middle digit on B

	bsf PORTA, 1		; Turn on only the middle display
	call Delay			; Wait
	bcf PORTA, 1		; Turn off the middle display

	movfw minutes		
	call BinaryToSevenSegment
	movwf PORTB			; Put the leftmost digit on B
	
	bsf PORTA, 2		; Turn on only the leftmost display
	call Delay			; Wait
	bcf PORTA, 2		; Turn off the leftmost display
		
	goto MAIN_LOOP

; ******************************************************
; * This subroutine takes a binary byte between 0 and  *
; * 9 and turns it into a seven-segment bitmap.        *
; * Input: a binary number in W between 0 and 9        *
; * Output: a seven-segment bitmap in W.               *
; ******************************************************
BinaryToSevenSegment
	addwf PCL,f			; Jump to entry specified by w.
	retlw b'10000000'		; 0
	retlw b'11110010'		; 1
	retlw b'01001000'		; 2
	retlw b'01100000'		; 3
	retlw b'00110010'		; 4
	retlw b'00100100'		; 5
	retlw b'00000100'		; 6
	retlw b'11110000'		; 7
	retlw b'00000000'		; 8
	retlw b'00110000'		; 9

; ******************************************************
; * This subroutine generates a short delay of         *
; * at least approx. 0.37 ms * (initial delay_count)   *
; * Note: the delay is not exact because interrupts    *
; * may occur during the loop.                         *
; ******************************************************
Delay	movlw 0x11
		movwf delay_count
Delay_loop
		decfsz delay_count,f		
		goto Delay_loop
		return   

; ******************************************************
; * This ISR is called in response to a TMR0 overflow. *
; * It decrements the minutes and seconds  variables   *
; * until they reach zero. At zero, it activates the   *
; * buzzer for 1 second and then puts the device in    *
; * sleep mode. When RBO is pressed, the device wakes  *
; * up.                                                *
; ******************************************************
ISR
	; Save the context
	movwf _work		; Put away W
	swapf STATUS,w	; and the Status register
	movwf _status

	; Check if this interrupt was triggered by RB0
	; changing or by a TMR0 overflow.
	btfss INTCON, INTF
	goto TIMER_TRIGGERED
BUTTON_TRIGGERED
	; Reset the interrupt flag
	bcf INTCON, INTF
	; This is a rising edge (the button is released
	; after being pressed), so we will start timing
	; at exactly this point.
	clrf TMR0;
	; Do not increment the time digits
	goto ISR_CLEANUP

TIMER_TRIGGERED
	; Reset the interrupt flag
	bcf INTCON,T0IF

	; If the button is pressed, don't increment
	; the time digits.
	btfss PORTB,0
	goto ISR_CLEANUP

INCREMENT_TIME

	movf secondsL,f
	btfss STATUS,Z	; If secondsL == 0, goto ZERO_SECL
	goto NONZERO_SECL
ZERO_SECL
	movf secondsH,f
	btfss STATUS,Z	; If secondsH == 0, goto ZERO_SECH
	goto NONZERO_SECH
ZERO_SECH
	movf minutes,f
	btfss STATUS,Z	; If minutes == 0, goto ZERO_MIN
	goto NONZERO_MIN
ZERO_MIN
	; Minutes and secondsH and secondsL are 0
	; Turn on the zero indicator (the buzzer on PORTA bit 3)
	bsf PORTA, 3

	; If (timeout-- == 0) then sleep until the button is released
	decfsz timeout,f
	goto ISR_CLEANUP

	; Turn off the zero indicator (the buzzer on PORTA bit 3)
	bcf PORTA, 3

	; Clear all of the displays
	movfw PORTA
	clrf PORTA			; Turn off all the displays

	sleep				; Wait for someone to press a button

	movwf PORTA			; Restore the previous PORTA value.
	
	movlw TIMEOUT_SECONDS	; Reset the timeout
	movwf timeout

	; Since the button is pressed, start from 3 min
	SetTimeTo3Min
	clrf TMR0	

	goto ISR_CLEANUP
		
NONZERO_MIN
	decf minutes,f	; minutes--
	movlw d'5'		
	movwf secondsH	
	movlw d'9'
	movwf secondsL ; seconds = 59	
	goto ISR_CLEANUP
NONZERO_SECH
	decf secondsH,f
	movlw d'9'
	movwf secondsL
	goto ISR_CLEANUP
NONZERO_SECL
	decf secondsL,f

ISR_CLEANUP
	; Restore the context
	swapf _status,w
	movwf STATUS
	swapf _work,f
	swapf _work,w
	retfie
	
	end
