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
    ;all probs start at 1/2
    mov edi, PROBS
    mov ecx, 640+2048
    mov ax, 2048
    rep stosw
    mov esi, payload
    lodsd
    mov edi, KERNEL
    lea eax, [edi+eax]
    mov [u_end], eax
    mov byte [edi-1], 0
    or ebp, -1
    lodsb
    lodsd
    bswap eax
    xchg ebx, eax
.next:
    cmp edi, [u_end]
    jae .undo
    ;lit or match
    mov eax, [u_was]
    call getbit
    jnz .match
    ; literal
    movzx edx, byte [edi-1]
    shr edx, 5
    shl edx, 8
    add edx, 640
    mov ecx, 1
.lit:
    lea eax, [edx+ecx]
    call getbit
    adc ecx, ecx
    cmp ecx, 256
    jb .lit
    xchg eax, ecx
    stosb
    and dword [u_was], 0
    jmp .next
.match:
    mov dword [u_was], 1
    ; rep match?
    mov al, 2
    call getbit
    jnz .rep
    mov edx, 320
    call gamma
    mov [u_off], ecx
.rep:
    mov edx, 8
    call gamma
    inc ecx
    push esi
    mov esi, edi
    sub esi, [u_off]
    rep movsb
    pop esi
    jmp .next

.undo:
    ; undo e8 filter
    mov esi, KERNEL
.f:
    mov eax, [u_end]
    sub eax, 4
    cmp esi, eax
    jae KERNEL
    lodsb
    cmp al, 0xE8
    jne .f
    lea eax, [esi+4-KERNEL]
    sub [esi], eax
    add esi, 4
    jmp .f

;elias gamma
gamma:
    xor ecx, ecx
.u:
    lea eax, [edx+ecx]
    call getbit
    jz .m
    inc ecx
    jmp .u
.m:
    mov eax, ecx
    shl eax, 4
    lea edx, [edx+eax+32]
    add edx, ecx
    mov eax, 1
    jecxz .x
.b:
    push eax
    lea eax, [edx-1]
    dec edx
    call getbit
    pop eax
    adc eax, eax
    loop .b
.x:
    xchg ecx, eax
    ret

getbit:
    push ecx
    push edx
    lea ecx, [PROBS+eax*2]
    movzx edx, word [ecx]
    mov eax, ebp
    shr eax, 12
    imul eax, edx
    cmp ebx, eax
    jae .one
    mov ebp, eax
    mov eax, 4096
    sub eax, edx
    shr eax, 4
    add [ecx], ax
    xor edx, edx
    jmp .n
.one:
    sub ebx, eax
    sub ebp, eax
    shr edx, 4
    sub [ecx], dx
    mov edx, 1
.n:
    cmp ebp, 1<<24
    jae .x
    shl ebp, 8
    shl ebx, 8
    lodsb
    mov bl, al
.x:
    mov eax, edx
    pop edx
    pop ecx
    shr eax, 1
    sbb eax, eax
    neg eax
    test eax, eax
    jz .z
    stc
    ret
.z:
    clc
    ret

u_end dd 0
u_was dd 0
u_off dd 0

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
    db 'one 16,384 byte image.', 10
fsreadme_end:

times IMGSEC*512-($-$$) db 0
