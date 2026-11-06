bits 16
org 0x7C00
%include "defs.inc"

; bios loads us at 7c00
start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    mov si, dap1
    mov ah, 0x42 ; read the rest
    int 0x13
    jmp stage2

; dap: size, count, buf, lba
dap1:
    db 16, 0
    dw IMGSEC-1
    dw 0, 0x07E0
    dq 1

bits 32
;32 bit from here
pm:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov esp, 0x7C00
    cld
    mov dword [packed], payload_end-$$      ;for ver / system window
    ; clear model tables
    mov edi, CMTAB
    mov ecx, 1<<21
    xor eax, eax
    rep stosd
    mov esi, payload
    lodsd ;unpacked size
    mov edi, KERNEL
    lea eax, [edi+eax]
    mov [u_end], eax
  ; ctx reads before the start
    and dword [edi-4], 0
    and dword [edi-8], 0
  ; range coder init
    or ebp, -1
    lodsb
    lodsd
    bswap eax
    xchg ebx, eax
.next:
    ; next byte
    cmp edi, [u_end]
    jae .undo
    pushad
    xor ecx, ecx
.h:
    movzx edx, byte [cm_mask+ecx]
    mov eax, edx
    mov esi, edi
.k:
    dec esi
    shr edx, 1
    jnc .ks
    imul eax, eax, 0x2F0B3
    movzx ebx, byte [esi]
    lea eax, [eax+ebx+1]
.ks:
    test edx, edx
    jnz .k
    mov [CMH+ecx*4], eax
    inc ecx
    cmp ecx, NM
    jb .h
    popad
    mov dword [CMPART], 1	; partial byte, 1 = sentinel
.bit:
    pushad
    xor ecx, ecx
    xor ebx, ebx
    xor ebp, ebp
.m:
    ; mix models, weight is a shift
    imul eax, [CMPART], 0x85EBCA6B
    imul edx, [CMH+ecx*4], 0x9E3779B1
    add eax, edx
    shr eax, 10
    lea eax, [CMTAB+eax*2]
    mov [CMK+ecx*4], eax
    movzx edx, byte [eax]
    movzx eax, byte [eax+1]
    push ecx
    mov cl, [cm_w+ecx]
    shl edx, cl
    shl eax, cl
    pop ecx
    add ebx, edx
    add ebp, eax
    inc ecx
    cmp ecx, NM
    jb .m
  ; p0=(2*n0+1)/(2*(n0+n1+1))
    lea ecx, [ebx+ebp+1]
    add ecx, ecx
    lea eax, [ebx*2+1]
    shl eax, 16
    xor edx, edx
    div ecx
    mov [CMPROB], eax
    popad
    mov eax, ebp
    shr eax, 16
    imul eax, [CMPROB]
    xor edx, edx
    cmp ebx, eax
    jae .one
    mov ebp, eax
    jmp .nb
.one:
    sub ebx, eax
    sub ebp, eax
    inc edx
.nb:
    ; normalize
    cmp ebp, 1<<24
    jae .nn
    shl ebp, 8
    shl ebx, 8
    lodsb
    mov bl, al
    jmp .nb
.nn:
    pushad
    xor ecx, ecx
.u:
    ;update counts
    mov eax, [CMK+ecx*4]
    cmp byte [eax+edx], 255
    je .c
    inc byte [eax+edx]
.c:
    xor edx, 1
    mov bl, [eax+edx]
    cmp bl, 2
    jbe .d
    shr bl, 1
    inc bl
    mov [eax+edx], bl
.d:
    xor edx, 1
    inc ecx
    cmp ecx, NM
    jb .u
    popad
    mov eax, [CMPART]
    add eax, eax
    or eax, edx
    mov [CMPART], eax
    cmp eax, 256
    jb .bit
    stosb ; got a byte
    jmp .next

.undo:
    ; undo the call filter
    mov esi, KERNEL
.f:
    mov eax, [u_end]
    sub eax, 4
    cmp esi, eax
    jae KERNEL ; go
    lodsb
    cmp al, 0xE8
    je .fix
    cmp al, 0xE9
    je .fix
    cmp al, 0x0F
    jne .f
    mov al, [esi]
    and al, 0xF0
    cmp al, 0x80
    jne .f
    inc esi
.fix:
    lea eax, [esi+4-KERNEL]
    sub [esi], eax
    add esi, 4
    jmp .f

; masks/weights from build.py
%include "cmtab.inc"

bits 16
times 510-($-$$) db 0
dw 0xAA55

;stage 2, still 16 bit
stage2:
  ;mode 13h,grab its palette for the games
    mov ax, 0x13
    int 0x10
    mov ax, 0x1017
    xor bx, bx
    mov cx, 256
    mov dx, 0x6800
    int 0x10
    ; 8x16 font -> 0x80000
    mov bh, 6
    xor di, di
    mov cx, 2048
    call bfont
    ; 8x8 font (games)
    mov bh, 3
    mov di, 0x1000
    mov cx, 512
    call bfont
    mov bh, 4
    mov di, 0x1400
    mov cx, 512
    call bfont

    ; find 1024x768x32 w/ lfb
    mov dword [0x6000], 'VBE2'
    mov ax, 0x4F00
    mov di, 0x6000
    int 0x10
    mov si, [0x600E]
    mov ax, [0x6010]
    mov fs, ax
.mode:
    mov cx, [fs:si]
    add si, 2
    cmp cx, 0xFFFF
    je .fail
    push si
    mov ax, 0x4F01
    mov di, 0x6200
    int 0x10
    pop si
    cmp word [0x6200+18], WIDTH
    jne .mode
    cmp word [0x6200+20], HEIGHT
    jne .mode
    cmp byte [0x6200+25], 32
    jne .mode
    test word [0x6200], 0x80
    jz .mode
    mov eax, [0x6200+40]
    mov [lfb], eax
    movzx eax, word [0x6200+16]
    mov [pitch], eax
    mov bx, cx
    or bx, 0x4000
    mov ax, 0x4F02
    int 0x10

    ; a20, gdt, pmode
    in al, 0x92
    or al, 2
    out 0x92, al
    cli
    lgdt [gdtr]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp dword 0x08:pm

.fail:
    hlt
    jmp .fail

; bh = font, cx = words
bfont:
    push cx
    push di
    mov ax, 0x1130
    int 0x10
    pop di
    pop cx
    push es
    pop ds
    mov si, bp
    mov ax, 0x8000
    mov es, ax
    rep movsw
    xor ax, ax
    mov ds, ax
    mov es, ax
    ret

gdt:
    dq 0
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
gdtr:
    dw 23
    dd gdt

u_end dd 0
u_was dd 0
u_off dd 0

payload:
    incbin "kernel.lz"
payload_end:
; dir lives in the last 128 bytes of this sector
times FSLBA*512+384-($-$$) db 0

; name 24, size, used
fsdir:
    db 'readme.txt'
    times 24-10 db 0
    dd fsreadme_end-fsreadme
    dd 1
    times 128-($-fsdir) db 0
fsreadme:
    db 'Welcome to XD OS.', 10, 10
    db 'The system and every file you save live in', 10
    db 'one 19,456 byte image.', 10
fsreadme_end:

times IMGSEC*512-($-$$) db 0
