bits 16
org 0x7C00

WIDTH   equ 1024
HEIGHT  equ 768
BACK    equ 0x1000000	;back buffer
WALL    equ 0x1400000               ;wallpaper
HILLT   equ 0x2000000
NOTE    equ 0x2100000
TBUF    equ 0x2110000
FONT    equ 0x80000                     ; bios font
FSMEM   equ 0x7C00+96*512
FSLBA   equ 96
FSMAX   equ 15
BARY    equ 728
NWIN    equ 9
WSIZE   equ 28
WX      equ 0
WY      equ 4
WW      equ 8
WH      equ 12
WVIS    equ 16
WTITLE  equ 20
MENUW   equ 240
MENUH   equ 56+(NWIN+1)*36
MENUY   equ BARY-MENUH
A_TERM  equ 1
A_NOTE  equ 2
A_FLAP  equ 5
A_HILL  equ 6
A_PAINT equ 7
A_BROWSE equ 8
CANVAS  equ 0x1800000
CANW    equ 420
CANH    equ 280

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
    mov ax, 0x1130
    ; 8x16 font -> 0x80000
    mov bh, 6
    int 0x10
    push es
    pop ds
    mov si, bp
    mov ax, 0x8000
    mov es, ax
    xor di, di
    mov cx, 2048
    rep movsw
    xor ax, ax
    mov ds, ax
    mov es, ax

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
    fninit
    cld
    mov al, 0x34
    out 0x43, al
    xor al, al
    out 0x40, al
    out 0x40, al
    call mouse_init
    call wallpaper
    mov edi, CANVAS
    mov ecx, CANW*CANH
    mov eax, 0xFFFFFF
    rep stosd
    call hill_init
    call browser_init
    call term_init
    call flap_reset
    mov dword [dirty], 1

main:
    call poll
    call clock_tick
    call ticker
    cmp dword [dirty], 0
    jne .full
    ; only the game changed
    cmp dword [gdirty], 0
    je main
    mov dword [gdirty], 0
    call fastframe
    jmp main
.full:
    mov dword [dirty], 0
    mov dword [gdirty], 0
    call scene
    cmp dword [b_go], 0
    je main
    call browser_go
    jmp main

fastframe:
    movzx ebp, byte [zord+NWIN-1]
    imul eax, ebp, WSIZE
    lea esi, [wins+eax]
    mov eax, [esi+WX]
    add eax, 6
    mov [cx0], eax
    mov eax, [esi+WY]
    add eax, 30
    mov [cy0], eax
    call [appdraw+ebp*4]
    call cursor
    imul eax, ebp, WSIZE
    lea esi, [wins+eax]
    mov eax, [cx0]
    mov ebx, [cy0]
    mov ecx, [esi+WW]
    sub ecx, 12
    mov edx, [esi+WH]
    sub edx, 36
    cmp eax, 0
    jge .a
    add ecx, eax
    xor eax, eax
.a:
    lea edi, [eax+ecx]
    cmp edi, WIDTH
    jle .b
    mov ecx, WIDTH
    sub ecx, eax
.b:
    lea edi, [ebx+edx]
    cmp edi, BARY
    jle .c
    mov edx, BARY
    sub edx, ebx
.c:
    cmp ecx, 0
    jle .x
    cmp edx, 0
    jle .x
    imul esi, ebx, WIDTH
    add esi, eax
    lea esi, [BACK+esi*4]
    imul edi, ebx, 1
    imul edi, [pitch]
    lea edi, [edi+eax*4]
    add edi, [lfb]
.r:
    push ecx
    push esi
    push edi
    rep movsd
    pop edi
    pop esi
    pop ecx
    add esi, WIDTH*4
    add edi, [pitch]
    dec edx
    jnz .r
.x:
    ret

; 39773 pit counts = ~30hz
ticker:
    mov al, 0
    out 0x43, al
    in al, 0x40
    mov ah, al
    in al, 0x40
    xchg al, ah
    movzx eax, ax
    mov ebx, [lastc]
    mov [lastc], eax
    sub ebx, eax
    and ebx, 0xFFFF
    add [tacc], ebx
    cmp dword [tacc], 39773
    jb .x
    sub dword [tacc], 39773
    cmp dword [tacc], 39773
    jb .go
    mov dword [tacc], 0
.go:
    movzx eax, byte [zord+NWIN-1]
    imul ebx, eax, WSIZE
    cmp dword [wins+ebx+WVIS], 0
    je .x
    cmp eax, A_FLAP
    je flap_tick
    cmp eax, A_HILL
    je hill_tick
.x:
    ret

kwait:
    in al, 0x64
    test al, 2
    jnz kwait
    ret

kread:
    in al, 0x64
    test al, 1
    jz kread
    in al, 0x60
    ret

kcmd:
    push eax
    call kwait
    pop eax
    out 0x64, al
    ret

kdata:
    push eax
    call kwait
    pop eax
    out 0x60, al
    ret

mwrite:
    push eax
    mov al, 0xD4
    call kcmd
    pop eax
    call kdata
    call kread
    ret

mouse_init:
    mov al, 0xA8
    call kcmd
    mov al, 0x20
    call kcmd
    call kread
    and al, 0xDC  ;no irqs,mouse clock on
    push eax
    mov al, 0x60
    call kcmd
    pop eax
    call kdata
    mov al, 0xF6
    call mwrite
    mov al, 0xF4	; enable reporting
    call mwrite
    ret

poll:
    in al, 0x64
    test al, 1
    jz .out
    mov ah, al
    in al, 0x60
    test ah, 0x20 ;mouse?
    jnz .mouse
    call key
    jmp poll
.mouse:
    call mbyte
    jmp poll
.out:
    ret

; bit 3 always set in byte 0, resync on it
mbyte:
    mov ebx, [midx]
    test ebx, ebx
    jnz .store
    test al, 8
    jz .done
.store:
    mov [mpkt+ebx], al
    inc ebx
    mov [midx], ebx
    cmp ebx, 3
    jb .done
    mov dword [midx], 0
    movzx eax, byte [mpkt+1]
    test byte [mpkt], 0x10
    jz .xp
    or eax, 0xFFFFFF00
.xp:
    add [mx], eax
    movzx eax, byte [mpkt+2]
    test byte [mpkt], 0x20
    jz .yp
    or eax, 0xFFFFFF00
.yp:
    sub [my], eax                   ;  y is flipped
    cmp dword [mx], 0
    jge .a
    mov dword [mx], 0
.a:
    cmp dword [mx], WIDTH-1
    jle .b
    mov dword [mx], WIDTH-1
.b:
    cmp dword [my], 0
    jge .c
    mov dword [my], 0
.c:
    cmp dword [my], HEIGHT-1
    jle .d
    mov dword [my], HEIGHT-1
.d:
    mov dword [dirty], 1
    movzx eax, byte [mpkt]
    and eax, 1
    mov ebx, [btn]
    mov [btn], eax
    cmp eax, ebx
    je .held
    test eax, eax
    jz .up
    call press
    jmp .held
.up:
    mov dword [drag], -1
.held:
    cmp dword [btn], 0
    je .done
    call dragging
.done:
    ret

dragging:
    mov eax, [drag]
    cmp eax, 0
    jl paint_stroke
    imul eax, WSIZE
    lea esi, [wins+eax]
    mov eax, [mx]
    sub eax, [dragx]
    mov [esi+WX], eax
    mov eax, [my]
    sub eax, [dragy]
    cmp eax, 0
    jge .ok
    xor eax, eax
.ok:
    mov [esi+WY], eax
.out:
    ret

press:
    cmp dword [menu], 0
    je .nomenu
    mov dword [menu], 0
    cmp dword [mx], MENUW
    jae .nomenu
    mov eax, [my]
    sub eax, MENUY+56
    cmp eax, (NWIN+1)*36
    jae .nomenu
    xor edx, edx
    mov ebx, 36
    div ebx
    cmp eax, NWIN
    je shutdown
    jmp open
.nomenu:
    cmp dword [my], BARY
    jl .wins
    cmp dword [mx], 104
    jae .bar
    mov dword [menu], 1
    ret
.bar:
    mov eax, [mx]
    sub eax, 112
    jb .ret
    xor edx, edx
    mov ebx, 94
    div ebx
    mov ecx, eax
    xor eax, eax
.b:
    imul ebx, eax, WSIZE
    cmp dword [wins+ebx+WVIS], 0
    je .bn
    dec ecx
    js open
.bn:
    inc eax
    cmp eax, NWIN
    jb .b
.ret:
    ret
.wins:
    mov ecx, NWIN-1
.w:
    movzx eax, byte [zord+ecx]
    mov ebx, eax
    imul eax, WSIZE
    lea esi, [wins+eax]
    cmp dword [esi+WVIS], 0
    je .next
    mov edx, [mx]
    sub edx, [esi+WX]
    cmp edx, [esi+WW]
    jae .next
    mov edi, [my]
    sub edi, [esi+WY]
    cmp edi, [esi+WH]
    jae .next
    mov eax, ebx
    call raise
    cmp edi, 28
    jae .client
    mov eax, [esi+WW]
    sub eax, 30
    cmp edx, eax
    jb .grab
    mov dword [esi+WVIS], 0
    ret
.grab:
    mov [drag], ebx
    mov [dragx], edx
    mov [dragy], edi
    ret
.client:
    lea ecx, [edx-6]
    lea edx, [edi-30]
    jmp [appclick+ebx*4]
.next:
    dec ecx
    jns .w
    cmp dword [mx], 96
    jae .ret
    mov eax, [my]
    sub eax, 12
    cmp eax, NWIN*78
    jae .ret
    xor edx, edx
    mov ebx, 78
    div ebx

open:
    push eax
    imul eax, WSIZE
    mov dword [wins+eax+WVIS], 1
    mov dword [dirty], 1
    pop eax

raise:
    pushad
    xor ecx, ecx
.f:
    cmp [zord+ecx], al
    je .s
    inc ecx
    cmp ecx, NWIN-1
    jb .f
.s:
    cmp ecx, NWIN-1
    jae .e
    mov bl, [zord+ecx+1]
    mov [zord+ecx], bl
    inc ecx
    jmp .s
.e:
    mov [zord+NWIN-1], al
    popad
nop_app:
    ret

; qemu acpi off
shutdown:
    mov dx, 0x604
    mov ax, 0x2000
    out dx, ax
.h:
    hlt
    jmp .h

key:
    cmp al, 0xE0                            ;ignore e0 prefix
    je .out
    movzx ebx, al
    and ebx, 0x7F
    mov ecx, 1
    test al, 0x80	; release?
    jz .st
    xor ecx, ecx
.st:
    mov [keys+ebx], cl
    cmp ebx, 0x2A
    je .sh
    cmp ebx, 0x36
    je .sh
    test al, 0x80
    jnz .out
    xor eax, eax
    cmp ebx, 0x0E
    je .bs
    cmp ebx, 0x1C
    je .nl
    cmp ebx, 0x39
    ja .send
    mov al, [keymap+ebx]
    test al, al
    jz .send
    cmp dword [shift], 0
    je .send
    cmp al, 'a'
    jb .sym
    cmp al, 'z'
    ja .sym
    sub al, 32
    jmp .send
.sym:
    mov esi, shiftmap
.sl:
    mov ah, [esi]
    test ah, ah
    jz .sc
    cmp ah, al
    je .sf
    add esi, 2
    jmp .sl
.sf:
    mov al, [esi+1]
.sc:
    xor ah, ah
    jmp .send
.nl:
    mov al, 10
    jmp .send
.bs:
    mov al, 8
.send:
    movzx ecx, byte [zord+NWIN-1]
    imul edx, ecx, WSIZE
    cmp dword [wins+edx+WVIS], 0
    je .out
    mov dword [dirty], 1
    jmp [appkey+ecx*4]
.sh:
    mov [shift], ecx
.out:
    ret

;bcd: ah tens, al ones
cmos:
    out 0x70, al
    in al, 0x71
    mov ah, al
    shr ah, 4
    and al, 15
    ret

clock_tick:
    mov al, 2		; minutes
    call cmos
    movzx ebx, al
    movzx ecx, ah
    cmp ebx, [lastmin]
    je .same
    mov [lastmin], ebx
    add cl, '0'
    add bl, '0'
    mov [clock+3], cl
    mov [clock+4], bl
    mov al, 4                       ; hours
    call cmos
    add ah, '0'
    add al, '0'
    mov [clock], ah
    mov [clock+1], al
    mov dword [dirty], 1
.same:
    ret

rand:
    imul eax, [seed], 1103515245
    add eax, 12345
    mov [seed], eax
    shr eax, 16
    ret

itoa:
    push ebx
    push ecx
    push edx
    mov esi, numbuf+15
    mov byte [esi], 0
    mov ebx, 10
    xor ecx, ecx
    test eax, eax
    jns .l
    neg eax
    inc ecx
.l:
    xor edx, edx
    div ebx
    add dl, '0'
    dec esi
    mov [esi], dl
    test eax, eax
    jnz .l
    test ecx, ecx
    jz .x
    dec esi
    mov byte [esi], '-'
.x:
    pop edx
    pop ecx
    pop ebx
    ret

;case insensitive
strcmp:
    push esi
    push edi
.l:
    mov al, [esi]
    cmp al, [edi]
    jne .x
    test al, al
    jz .x
    inc esi
    inc edi
    jmp .l
.x:
    pop edi
    pop esi
    ret

lerp:
    push ebx
    push ecx
    push edx
    push edi
    xor edi, edi
    xor ecx, ecx
.c:
    mov eax, [g_c2]
    shr eax, cl
    and eax, 255
    mov ebx, [g_c1]
    shr ebx, cl
    and ebx, 255
    sub eax, ebx
    imul eax, ebp
    cdq
    idiv dword [g_h]
    add eax, ebx
    and eax, 255
    shl eax, cl
    or edi, eax
    add cl, 8
    cmp cl, 24
    jb .c
    mov eax, edi
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

rect:
    pushad
    cmp eax, 0
    jge .a
    add ecx, eax
    xor eax, eax
.a:
    cmp ebx, 0
    jge .b
    add edx, ebx
    xor ebx, ebx
.b:
    lea edi, [eax+ecx]
    cmp edi, WIDTH
    jle .c
    mov ecx, WIDTH
    sub ecx, eax
.c:
    lea edi, [ebx+edx]
    cmp edi, HEIGHT
    jle .d
    mov edx, HEIGHT
    sub edx, ebx
.d:
    cmp ecx, 0
    jle .x
    cmp edx, 0
    jle .x
    imul edi, ebx, WIDTH
    add edi, eax
    lea edi, [BACK+edi*4]
    mov eax, esi
.y:
    push ecx
    push edi
    rep stosd
    pop edi
    pop ecx
    add edi, WIDTH*4
    dec edx
    jnz .y
.x:
    popad
    ret

; 3/4
shade:
    pushad
    cmp eax, 0
    jge .a
    add ecx, eax
    xor eax, eax
.a:
    lea edi, [eax+ecx]
    cmp edi, WIDTH
    jle .c
    mov ecx, WIDTH
    sub ecx, eax
.c:
    lea edi, [ebx+edx]
    cmp edi, HEIGHT
    jle .d
    mov edx, HEIGHT
    sub edx, ebx
.d:
    cmp ecx, 0
    jle .x
    cmp edx, 0
    jle .x
    imul edi, ebx, WIDTH
    add edi, eax
    lea edi, [BACK+edi*4]
.y:
    push ecx
    push edi
.p:
    mov eax, [edi]
    mov ebx, eax
    shr eax, 1
    and eax, 0x7F7F7F
    shr ebx, 2
    and ebx, 0x3F3F3F
    add eax, ebx
    stosd
    dec ecx
    jnz .p
    pop edi
    pop ecx
    add edi, WIDTH*4
    dec edx
    jnz .y
.x:
    popad
    ret

; g_round: 1 top corners,2 all
grad:
    pushad
    mov [g_x], eax
    mov [g_y], ebx
    mov [g_w], ecx
    mov [g_h], edx
    mov [g_c1], esi
    mov [g_c2], edi
    xor ebp, ebp
.l:
    cmp ebp, [g_h]
    jge .x
    call lerp
    mov esi, eax
    xor edi, edi
    cmp dword [g_round], 0
    je .draw
    cmp ebp, 5
    jae .bot
    movzx edi, byte [rnd+ebp]
.bot:
    cmp dword [g_round], 2
    jne .draw
    mov eax, [g_h]
    dec eax
    sub eax, ebp
    cmp eax, 5
    jae .draw
    movzx edi, byte [rnd+eax]
.draw:
    mov eax, [g_x]
    add eax, edi
    mov ebx, [g_y]
    add ebx, ebp
    mov ecx, [g_w]
    sub ecx, edi
    sub ecx, edi
    mov edx, 1
    call rect
    inc ebp
    jmp .l
.x:
    popad
    ret

rbox:
    push edi
    mov edi, esi
    mov dword [g_round], 2
    call grad
    mov dword [g_round], 0
    pop edi
    ret

rgrad:
    mov dword [g_round], 2
    call grad
    mov dword [g_round], 0
    ret

; alpha eax/15
blend:
    push ebx
    push ecx
    push edx
    cmp eax, 15
    jne .b
    mov edx, [a_col]
    mov [edi], edx
    jmp .x
.b:
    imul eax, 17
    mov ebx, 255
    sub ebx, eax
    mov ecx, [edi]
    mov edx, ecx
    and ecx, 0xFF00FF
    and edx, 0x00FF00
    imul ecx, ebx
    imul edx, ebx
    mov ebx, [a_col]
    and ebx, 0xFF00FF
    imul ebx, eax
    add ecx, ebx
    mov ebx, [a_col]
    and ebx, 0x00FF00
    imul ebx, eax
    add edx, ebx
    shr ecx, 8
    and ecx, 0xFF00FF
    shr edx, 8
    and edx, 0x00FF00
    or ecx, edx
    mov [edi], ecx
.x:
    pop edx
    pop ecx
    pop ebx
    ret

; 4 bit alpha
ablit:
    pushad
    mov [a_x], eax
    mov [a_w], ecx
    mov [a_col], edx
    inc ecx
    shr ecx, 1
    mov [a_st], ecx
.row:
    cmp ebx, HEIGHT
    jae .next
    xor ecx, ecx
.p:
    mov eax, ecx
    shr eax, 1
    movzx eax, byte [esi+eax]
    test cl, 1
    jnz .lo
    shr eax, 4
.lo:
    and eax, 15
    jz .n
    mov edi, [a_x]
    add edi, ecx
    cmp edi, WIDTH
    jae .n
    imul edx, ebx, WIDTH
    add edi, edx
    lea edi, [BACK+edi*4]
    call blend
.n:
    inc ecx
    cmp ecx, [a_w]
    jb .p
.next:
    add esi, [a_st]
    inc ebx
    dec ebp
    jnz .row
    popad
    ret

nib:
    mov eax, ecx
    shr eax, 1
    movzx eax, byte [edx+eax]
    test cl, 1
    jnz .lo
    shr eax, 4
.lo:
    and eax, 15
    ret

cicon:
    pushad
    imul edi, edi, ICONSZ
    lea esi, [iconset+edi]
    mov [a_x], eax
    mov [ci_y], ebx
    mov [ci_s], ebp
    mov dword [ci_r], 0
.row:
    mov dword [ci_c], 0
.col:
    imul ecx, [ci_r], 48
    add ecx, [ci_c]
    lea edx, [esi+64+1152]
    call nib
    test eax, eax
    jz .n
    mov ebx, eax
    lea edx, [esi+64]
    call nib
    mov eax, [esi+eax*4]
    mov [a_col], eax
    mov eax, [ci_c]
    xor edx, edx
    div dword [ci_s]
    add eax, [a_x]
    mov edi, eax
    cmp edi, WIDTH
    jae .n
    mov eax, [ci_r]
    xor edx, edx
    div dword [ci_s]
    add eax, [ci_y]
    cmp eax, HEIGHT
    jae .n
    imul eax, WIDTH
    add edi, eax
    lea edi, [BACK+edi*4]
    mov eax, ebx
    call blend
.n:
    mov eax, [ci_s]
    add [ci_c], eax
    cmp dword [ci_c], 48
    jb .col
    mov eax, [ci_s]
    add [ci_r], eax
    cmp dword [ci_r], 48
    jb .row
    popad
    ret

text:
    pushad
.n:
    movzx ecx, byte [esi]
    test ecx, ecx
    jz .x
    sub ecx, 32
    cmp ecx, 95
    jae .sk
    push esi
    movzx esi, word [fonto+ecx*2]
    add esi, fontd
    movzx ecx, byte [fontw+ecx]
    mov ebp, FH
    call ablit
    add eax, ecx
    pop esi
.sk:
    inc esi
    jmp .n
.x:
    popad
    ret

twidth:
    push ecx
    push esi
    xor eax, eax
.n:
    movzx ecx, byte [esi]
    test ecx, ecx
    jz .x
    sub ecx, 32
    cmp ecx, 95
    jae .s
    movzx ecx, byte [fontw+ecx]
    add eax, ecx
.s:
    inc esi
    jmp .n
.x:
    pop esi
    pop ecx
    ret

glyph:
    pushad
    mov [t_x], eax
    shl ecx, 4
    lea esi, [ecx+FONT]
    mov ebp, 16
.row:
    lodsb
    cmp ebx, HEIGHT
    jae .next
    mov cl, al
    mov edi, [t_x]
    mov ch, 8
.b:
    test cl, 0x80
    jz .s
    cmp edi, WIDTH
    jae .s
    imul eax, ebx, WIDTH
    add eax, edi
    mov [BACK+eax*4], edx
.s:
    shl cl, 1
    inc edi
    dec ch
    jnz .b
.next:
    inc ebx
    dec ebp
    jnz .row
    popad
    ret

; sunset
wallpaper:
    xor ebp, ebp
    mov dword [g_h], 600
    mov dword [g_c1], 0x1A1250
    mov dword [g_c2], 0xFF8A5C
    mov edi, WALL
.sky:
    mov eax, 0xFF8A5C
    cmp ebp, 600
    jge .s2
    call lerp
.s2:
    mov ecx, WIDTH
    rep stosd
    inc ebp
    cmp ebp, HEIGHT
    jl .sky

    mov ebp, 220
.star:
    call rand
    and eax, 1023
    mov ebx, eax
    call rand
    xor edx, edx
    mov ecx, 300
    div ecx
    imul edx, WIDTH
    add edx, ebx
    mov dword [WALL+edx*4], 0xE8E4FF
    dec ebp
    jnz .star

    mov ebx, -80
.sy:
    mov ecx, -80
.sx:
    mov eax, ebx
    imul eax, eax
    mov edx, ecx
    imul edx, edx
    add eax, edx
    cmp eax, 6400
    jg .sn
    lea eax, [ebx+470]
    imul eax, WIDTH
    lea eax, [eax+ecx+720]
    mov dword [WALL+eax*4], 0xFFE3A1
.sn:
    inc ecx
    cmp ecx, 80
    jle .sx
    inc ebx
    cmp ebx, 80
    jle .sy

    mov esi, ridges
    mov ebp, 3
.layer:
    xor ecx, ecx
.col:
    mov [t_x], ecx
    fild dword [t_x]
    fmul dword [esi+4]
    fsin
    fmul dword [esi+8]
    fild dword [t_x]
    fmul dword [esi+12]
    fsin
    fmul dword [esi+16]
    faddp
    fiadd dword [esi]
    fistp dword [t_y]
    mov ebx, [t_y]
    imul edi, ebx, WIDTH
    add edi, ecx
    lea edi, [WALL+edi*4]
    mov eax, [esi+20]
.fill:
    mov [edi], eax
    add edi, WIDTH*4
    inc ebx
    cmp ebx, HEIGHT
    jl .fill
    inc ecx
    cmp ecx, WIDTH
    jl .col
    add esi, 24
    dec ebp
    jnz .layer
    ret

window:
    pushad
    mov ebp, eax
    imul eax, WSIZE
    lea esi, [wins+eax]
    cmp dword [esi+WVIS], 0
    je .x
    mov [cur], esi
    mov eax, [esi+WX]
    mov ebx, [esi+WY]
    mov ecx, [esi+WW]
    mov edx, [esi+WH]
    add eax, 5
    add ebx, 6
    call shade
    add eax, 3
    add ebx, 3
    call shade
    sub eax, 8
    sub ebx, 9
    mov esi, 0x20243A
    call rbox
    inc eax
    inc ebx
    sub ecx, 2
    sub edx, 2
    mov esi, 0xF6F4F0
    call rbox
    movzx edi, byte [zord+NWIN-1]
    cmp edi, ebp
    jne .inact
    mov esi, 0x2F6BFF
    mov edi, 0x7A3CF0
    jmp .tb
.inact:
    mov esi, 0x9094A8
    mov edi, 0x70748C
.tb:
    mov edx, 27
    mov dword [g_round], 1
    call grad
    mov dword [g_round], 0
    mov esi, [cur]
    mov edx, 0xFFFFFF
    add eax, 10
    add ebx, 4
    mov esi, [esi+WTITLE]
    call text
    mov esi, [cur]
    mov eax, [esi+WX]
    add eax, [esi+WW]
    sub eax, 27
    mov ebx, [esi+WY]
    add ebx, 5
    mov ecx, 20
    mov edx, 18
    mov esi, 0xE5484D
    call rbox
    add eax, 6
    mov ecx, 'x'
    mov edx, 0xFFFFFF
    call glyph
    mov esi, [cur]
    mov eax, [esi+WX]
    add eax, 6
    mov [cx0], eax
    mov ebx, [esi+WY]
    add ebx, 30
    mov [cy0], ebx
    call [appdraw+ebp*4]
.x:
    popad
    ret

icons:
    xor ebp, ebp
.i:
    push ebp
    mov eax, 24
    imul ebx, ebp, 78
    add ebx, 12
    mov edi, ebp
    mov ebp, 1
    call cicon
    pop ebp
    mov esi, [titles+ebp*4]
    call twidth
    shr eax, 1
    neg eax
    add eax, 48
    add ebx, 52
    inc eax
    inc ebx
    mov edx, 0x000000
    call text
    dec eax
    dec ebx
    mov edx, 0xFFFFFF
    call text
    inc ebp
    cmp ebp, NWIN
    jb .i
    ret

taskbar:
    xor eax, eax
    mov ebx, BARY
    mov ecx, WIDTH
    mov edx, HEIGHT-BARY
    mov esi, 0x2A2F52
    mov edi, 0x12142C
    call grad
    mov eax, 6
    mov ebx, BARY+6
    mov ecx, 92
    mov edx, 28
    mov esi, 0x35C98A
    mov edi, 0x128A5A
    cmp dword [menu], 0
    je .sb
    xchg esi, edi
.sb:
    call rgrad
    add eax, 30
    add ebx, 5
    mov esi, s_start
    mov edx, 0xFFFFFF
    call text
    xor ebp, ebp
    mov dword [t_y], 0
.t:
    imul edx, ebp, WSIZE
    cmp dword [wins+edx+WVIS], 0
    je .n
    imul eax, [t_y], 94
    add eax, 112
    inc dword [t_y]
    mov ebx, BARY+6
    mov ecx, 90
    mov edx, 28
    mov esi, 0x3C4270
    movzx edi, byte [zord+NWIN-1]
    cmp edi, ebp
    jne .tb
    mov esi, 0x5A63A8
.tb:
    call rbox
    add eax, 10
    add ebx, 5
    mov esi, [titles+ebp*4]
    mov edx, 0xFFFFFF
    call text
.n:
    inc ebp
    cmp ebp, NWIN
    jb .t
    mov eax, WIDTH-52
    mov ebx, BARY+11
    mov esi, clock
    mov edx, 0xFFFFFF
    call text
    ret

startmenu:
    cmp dword [menu], 0
    je .x
    xor eax, eax
    mov ebx, MENUY
    mov ecx, MENUW
    mov edx, MENUH
    mov esi, 0xF6F4F0
    call rect
    mov edx, 56
    mov esi, 0x2F6BFF
    mov edi, 0x7A3CF0
    call grad
    add eax, 16
    add ebx, 19
    mov esi, s_name
    mov edx, 0xFFFFFF
    call text
    xor ebp, ebp
.i:
    imul ebx, ebp, 36
    add ebx, MENUY+56
    mov eax, [my]
    sub eax, ebx
    cmp eax, 36
    jae .nh
    cmp dword [mx], MENUW
    jae .nh
    xor eax, eax
    mov ecx, MENUW
    mov edx, 36
    mov esi, 0xCFD8FF
    call rect
.nh:
    cmp ebp, NWIN
    jae .lbl
    push ebp
    mov eax, 12
    add ebx, 6
    mov edi, ebp
    mov ebp, 2
    call cicon
    pop ebp
    sub ebx, 6
.lbl:
    mov eax, 48
    add ebx, 9
    mov esi, [titles+ebp*4]
    mov edx, 0x20243A
    call text
    inc ebp
    cmp ebp, NWIN+1
    jb .i
.x:
    ret

cursor:
    mov esi, arrow
    xor ebp, ebp
.r:
    xor ecx, ecx
.c:
    mov al, [esi]
    inc esi
    cmp al, '.'
    je .n
    mov edx, 0x000000
    cmp al, 'X'
    je .p
    mov edx, 0xFFFFFF
.p:
    mov eax, [mx]
    add eax, ecx
    cmp eax, WIDTH
    jae .n
    mov ebx, [my]
    add ebx, ebp
    cmp ebx, HEIGHT
    jae .n
    imul ebx, WIDTH
    add ebx, eax
    mov [BACK+ebx*4], edx
.n:
    inc ecx
    cmp ecx, 11
    jb .c
    inc ebp
    cmp ebp, 16
    jb .r
    ret

scene:
    mov esi, WALL
    mov edi, BACK
    mov ecx, WIDTH*HEIGHT
    rep movsd
    call icons
    xor ecx, ecx
.w:
    movzx eax, byte [zord+ecx]
    call window
    inc ecx
    cmp ecx, NWIN
    jb .w
    call taskbar
    call startmenu
    call cursor
    mov esi, BACK
    mov edi, [lfb]
    mov edx, HEIGHT
.b:
    push esi
    push edi
    mov ecx, WIDTH
    rep movsd
    pop edi
    pop esi
    add esi, WIDTH*4
    add edi, [pitch]
    dec edx
    jnz .b
    ret

%include "fs.inc"
%include "apps.inc"
%include "games.inc"
%include "net.inc"
%include "browser.inc"

lfb     dd 0
pitch   dd 0
mx      dd 512
my      dd 384
btn     dd 0
midx    dd 0
mpkt    db 0, 0, 0, 0
drag    dd -1
dragx   dd 0
dragy   dd 0
menu    dd 0
dirty   dd 0
gdirty  dd 0
shift   dd 0
lastmin dd 99
lastc   dd 0
tacc    dd 0
seed    dd 0x13572468
cur     dd 0
cx0     dd 0
cy0     dd 0
t_x     dd 0
t_y     dd 0
g_x     dd 0
g_y     dd 0
g_w     dd 0
g_h     dd 1
g_c1    dd 0
g_c2    dd 0
g_round dd 0
a_x     dd 0
a_w     dd 0
a_st    dd 0
a_col   dd 0
ci_y    dd 0
ci_r    dd 0
ci_c    dd 0
ci_s    dd 1
rnd     db 5, 3, 2, 1, 1
numbuf  times 16 db 0
keys    times 128 db 0
zord    db 1, 2, 3, 4, 5, 6, 7, 8, 0		; last = top
pcolor  dd 0x20243A
swatches dd 0x20243A, 0xE5484D, 0xF0A020, 0x35C98A, 0x2F6BFF, 0xFFFFFF
clock   db '00:00', 0

wins:
    dd 150, 60, 440, 230, 1, s_sys, 0
    dd 230, 120, 636, 420, 0, s_term, 0
    dd 300, 170, 452, 340, 0, s_note, 0
    dd 120, 150, 372, 420, 0, s_files, 0
    dd 660, 100, 248, 330, 0, s_calc, 0
    dd 360, 80, 332, 396, 0, s_flap, 0
    dd 280, 180, 492, 336, 0, s_hill, 0
    dd 420, 90, 434, 346, 0, s_paint, 0
    dd 140, 40, 740, 560, 0, s_browse, 0

titles  dd s_sys, s_term, s_note, s_files, s_calc, s_flap, s_hill, s_paint, s_browse, s_off
appdraw dd draw_sys, draw_term, draw_note, draw_files, draw_calc, draw_flap, draw_hill, draw_paint, draw_browser
appclick dd nop_app, nop_app, click_note, click_files, click_calc, click_flap, nop_app, nop_app, click_browser
appkey  dd nop_app, key_term, key_note, nop_app, nop_app, key_flap, nop_app, nop_app, key_browser

; y, f, a, f, a, color
ridges:
    dd 600
    dd 0.0061, 42.0, 0.017, 16.0
    dd 0x6A2E7A
    dd 640
    dd 0.0043, 34.0, 0.013, 14.0
    dd 0x43206A
    dd 690
    dd 0.0077, 22.0, 0.021, 9.0
    dd 0x21123F

s_sys   db 'System', 0
s_term  db 'Terminal', 0
s_note  db 'Notepad', 0
s_files db 'Files', 0
s_calc  db 'Calculator', 0
s_flap  db 'Flap', 0
s_hill  db 'Hill Ride', 0
s_paint db 'Paint', 0
s_browse db 'Browser', 0
s_off   db 'Shut down', 0
s_start db 'Start', 0
s_name  db 'XD OS', 0

keymap:
    db 0, 0, '1234567890-=', 0, 0
    db 'qwertyuiop[]', 0, 0
    db 'asdfghjkl;', 39, '`', 0, '\'
    db 'zxcvbnm,./', 0, '*', 0, ' '

shiftmap:
    db '1!2@3#4$5%6^7&8*9(0)-_=+[{]};:', 39, '"', ',<.>/?\|`~', 0

arrow:
    db 'X..........'
    db 'XX.........'
    db 'XoX........'
    db 'XooX.......'
    db 'XoooX......'
    db 'XooooX.....'
    db 'XoooooX....'
    db 'XooooooX...'
    db 'XoooooooX..'
    db 'XooooooooX.'
    db 'XoooooXXXXX'
    db 'XooXooX....'
    db 'XoX.XooX...'
    db 'XX..XooX...'
    db 'X....XooX..'
    db '.....XXX...'

%include "assets.inc"

code_end:
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
