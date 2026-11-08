;   File: START.ASM
;   Main driver for HELLDPMI
;   Copyright (c) 2025 by Will Klees

.386P

INCLUDE INT2FAPI.INC
INCLUDE INT31.INC
INCLUDE DOS.INC


; Segment arrangement
STACK SEGMENT STACK 'STACK'                         ; 16-bit stack
    DW 40H dup(0)
STACK ENDS

TEXT SEGMENT USE16 PARA PUBLIC 'CODE'               ; 16-bit code segment
TEXT ENDS

_TEXT SEGMENT USE32 PARA PUBLIC 'CODE'              ; 32-bit code segment
_TEXT ENDS

_DATA SEGMENT USE32 PARA PUBLIC 'DATA'
_DATA ENDS

PROG_END SEGMENT                                    ; End of program mark
PROG_END ENDS


TEXT SEGMENT USE16 PARA PUBLIC 'CODE'                          ; Far pointer to mode switch routine

;   MAIN procedure - The entry point of HELLDPMI. Once invoked, the entry point
;   executes the following steps
;   1.) Set up segment registers
;   2.) Release all unneeded memory back to DOS
;   3.) Retrieve the DPMI protected-mode switch entry point, checking if there
;       even is a resident DPMI server, and if it supports 32-bit clients.
;   4.) Allocate the required memory for the DPMI server
;   5.) Call the entry point to switch into protected-mode
;   6.) Allocate a data descriptor: this is accomplished using the "Segment to
;       Selector" DPMI call that takes a real-mode paragraph address and
;       returns a protected-mode segment selector with the same linear address
;       (set as a data segment with a limit of 64K). We use the _DATA segment
;       as the 32-bit data area
;   7.) Allocate a descriptor for code using the same process as #6, but based
;       at _TEXT instead
;   8.) Set code descriptor access rights (i.e. to specify that the code
;       segment is a use32 code segment)
;   9.) Set all of the data segment registers to the data selector obtained in
;       #6
;   10.)Build a far return frame to return into a 32-bit context and then RETFD
;
;   Parameters:
;   - ES=DS: Paragraph address of PSP

MAIN PROC FAR PUBLIC
    ASSUME DS:_DATA

    PUSH _DATA                          ; 1. Set memory model
    POP DS

    MOV AH,DOS_SETBLK                   ; 2. Free memory
    MOV BX,PROG_END
    SUB BX,STACK
    ADD BX,10H
    INT INT_DOS

                                        ; 3. Obtain DPMI entry point
    MOV AX,((W386_Int_Multiplex SHL 8) OR W386_Get_PM_Switch_Addr)
    INT W386_API_Int
    OR AX,AX                            ; AX is nonzero if the call failed
    JNZ error1
    TEST BL,1                           ; Are 32-bit programs supported?
    JZ error2
    MOV WORD PTR [MODESW],DI
    MOV WORD PTR [MODESW+2],ES
    MOV BX,SI                           ; 4. Allocate memory for DPMI data
    MOV AH,DOS_ALLOC
    INT INT_DOS
    JC error3
    MOV ES,AX
    MOV AX,1                            ; 5. Switch to protected mode (32-bit)
    CALL DWORD PTR [MODESW]
    JC error3
                                        ; 6. Allocate descriptor for data
    MOV AX,((Int31_Sel_Mgt SHL 8) OR SelMgt_Seg_To_Sel)
    MOV BX,_DATA
    INT 31H
    MOV SI,AX
                                        ; 7. Allocate descriptor for code
    MOV AX,((Int31_Sel_Mgt SHL 8) OR SelMgt_Seg_To_Sel)
    MOV BX,_TEXT
    INT 31H
    MOV DI,AX
    MOV BX,AX                           ; 8. Set code descriptor access rights
    MOV AX,((Int31_Sel_Mgt SHL 8) OR SelMgt_Set_Acc_Bits)
    MOV DX,CS
    LAR CX,DX
    SHR CX,8
    OR CX,0C000h
    INT 31H

    MOV DS,SI                           ; 9. Set all data segment registers to
    MOV ES,SI                           ; the data segment from #6
    MOV FS,SI
    MOV GS,SI
    PUSH 0                              ; 10. Push far return frame and RETFD!
    PUSH DI
    PUSH OFFSET MAIN32
    db 66h
    RETF

done16:
    MOV AH, DOS_EXIT
    INT INT_DOS

error1:
    MOV DX,OFFSET ERROR1T
    JMP error
error2:
    MOV DX,OFFSET ERROR2T
    JMP error
error3:
    MOV DX,OFFSET ERROR3T
    JMP error

error:
    MOV AH,DOS_PRINT
    INT 21H

    MOV AH,DOS_EXIT
    INT 21H

MAIN ENDP


RMPROC PROC FAR PUBLIC
	mov	ah,9
	mov	dx,offset hello16
	int	21h

	mov	ax,2501h
	mov	dx,offset divhndlr
	push	ds
	push	cs
	pop	ds
	int	21h
	pop	ds

	mov     word ptr fpCmdTail,offset cmdline
	mov	word ptr fpCmdTail+2,ds
	mov	word ptr fpFcb0,offset fcb
	mov	word ptr fpFcb0+2,ds
	mov	word ptr fpFcb1,offset fcb
	mov	word ptr fpFcb1+2,ds

	mov	ax,ds
	mov	es,ax
	mov	ax,4b00h
	mov	dx,offset pgmname
	mov	bx,offset execblock
	int	21h

	retf
RMPROC ENDP

divhndlr proc far public
	pusha

	mov	ah,9
	mov	dx,offset divfault
	push	ds
	push	_DATA
	pop	ds
	int	21h
	pop	ds

	popa

	iret
divhndlr endp


TEXT ENDS
               

_TEXT SEGMENT USE32 PARA PUBLIC 'CODE'

;   MAIN32 procedure - The 32-bit entry point that sets up a 32-bit stack,
;   prints hello world and exits.
;
;   Execution environment:
;   - CS: use32 code selector based at _TEXT
;   - DS=ES=FS=GS: data selector based at _DATA

MAIN32 PROC NEAR PUBLIC
    MOV AX,DS                   ; Set up 32-bit stack
    MOV SS,AX
    MOV ESP,OFFSET STACK32

    MOV EDX,OFFSET hello
    MOV AH,DOS_PRINT
    INT INT_DOS
 
    movzx eax,word ptr MODESW+2
    movzx ebx,word ptr MODESW
    shl eax,4
    add eax,ebx

    mov cx,ax
    shr eax,16
    mov bx,ax
    mov dl,0
    mov dh,0
    mov ax,0b00h
    int 31h
    jc fail

    mov rDS,_DATA
    mov rIP,offset RMPROC
    mov rCS,TEXT
    
    mov ax,301h
    mov bh,0
    mov cx,0
    mov edi,offset rm_regs
    int 31h

    MOV AH,DOS_EXIT
    INT INT_DOS

fail:
    mov ah,9
    mov edx,offset fail_wp
    int 21h

    MOV AH,DOS_EXIT
    INT INT_DOS
MAIN32 ENDP

print_dword proc near public
    push ebp
    mov ebp, esp
    mov eax, dword ptr [ebp+8]
    xor edx, edx
    mov ecx, 10000000h
    mov ebx, offset charset

    print_word_loop:
        div ecx
        mov ah, 0eh
        xlat
        int 10h
        mov eax, edx
        xor edx, edx
        shr ecx, 4
        cmp ecx, 0
        jne print_word_loop

    pop ebp
    ret 4
print_dword endp


_TEXT ENDS



_DATA SEGMENT USE32 PARA PUBLIC 'DATA'
    ERROR1T DB "ERROR: DPMI host not present!$"
    ERROR2T DB "ERROR: DPMI host is 16-bit only!$"
    ERROR3T DB "ERROR: Fatal DPMI error!$"
    MODESW  DD 0
    hello db "Hello, world from 32-bit protected mode!$"
    hello16 db "Hello, world from virtual 8086 mode!$"
    fail_wp db "Failed to set 80386 debug breakpoint$"
    divfault db "Debug fault$"
    pgmname db "16.exe",0
charset         db "0123456789ABCDEF"
cmdline db 1,0Dh

execblock LABEL BYTE
envSeg dw 0	; 0=inherit
fpCmdTail dd 0	; 
fpFcb0    dd 0
fpFcb1    dd 0

fcb LABEL BYTE
db 0
db '           '
db 0,0,0,0

rm_regs LABEL BYTE
rDI dd 0
rSI dd 0
rBP dd 0
rIgnored dd 0
rBX dd 0
rDX dd 0
rCX dd 0
rAX dd 0
rFLAGS dw 0
rES dw 0
rDS dw 0
rFS dw 0
rGS dw 0
rIP dw 0
rCS dw 0
rSP dw 0
rSS dw 0

    ALIGN 4
    dd 64 dup (?)
    STACK32 LABEL BYTE
_DATA ENDS

END MAIN
