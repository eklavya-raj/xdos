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
    mov [drive], dl
    mov si, dap1
    mov ah, 0x42 ; read the rest
    int 0x13
    mov si, dap2
    mov ah, 0x42
    mov dl, [drive]
    int 0x13
    jmp stage2

drive db 0
; dap: size, count, buf, lba
dap1:
    db 16, 0
    dw 64
    dw 0, 0x07E0
    dq 1
dap2:
    db 16, 0
    dw 63
    dw 0, 0x0FE0
    dq 65

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

bits 32
pm:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    mov esp, 0x7C00
    cld
    mov dword [packed], payload_end-$$
    mov esi, payload
    lodsd
    mov edi, KERNEL
    lea ebp, [edi+eax]
.flags:
    lodsb
    ; lz: flag byte then 8 items
    mov dl, al
    mov dh, 8
.bit:
    cmp edi, ebp
    jae KERNEL
    shr dl, 1
    jnc .copy
    movsb
    jmp .next
.copy:
    lodsw
    ;  len low 5 bits +3, offset +1
    movzx ecx, ax
    and ecx, 31
    add ecx, 3
    movzx eax, ax
    shr eax, 5
    inc eax
    push esi
    mov esi, edi
    sub esi, eax
    rep movsb
    pop esi
.next:
    dec dh
    jnz .bit
    jmp .flags

payload:
    incbin "kernel.lz"
payload_end:
times FSLBA*512-($-$$) db 0

; name 24, size, used
fsdir:
    db 'readme.txt'
    times 24-10 db 0
    dd fsreadme_end-fsreadme
    dd 1
    times 512-($-fsdir) db 0
fsreadme:
    db 'Welcome to XD OS.', 10, 10
    db 'The system and every file you save live in', 10
    db 'one 65,536 byte image.', 10
fsreadme_end:

times 65536-($-$$) db 0
