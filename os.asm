bits 16
org 0x7C00

WIDTH   equ 1024
HEIGHT  equ 768
BACK    equ 0x1000000	;back buffer
WALL    equ 0x1400000               ;wallpaper
CANVAS  equ 0x1800000
FONT    equ 0x80000                     ; bios font
BARY    equ 728
WSIZE   equ 28
WX      equ 0
WY      equ 4
WW      equ 8
WH      equ 12
WVIS    equ 16
WTITLE  equ 20
CANW      equ 420
CANH      equ 280

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
    call mouse_init
    call wallpaper
    mov edi, CANVAS
    mov ecx, CANW*CANH
    mov eax, 0xFFFFFF
    rep stosd
    mov dword [dirty], 1

main:
    call poll
    call clock_tick
    cmp dword [dirty], 0
    je main
    mov dword [dirty], 0
    call scene
    jmp main

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
    jl .paint
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
    ret
.paint:
    movzx eax, byte [zord+2]
    cmp eax, 2
    jne .out
    lea esi, [wins+2*WSIZE]
    cmp dword [esi+WVIS], 0
    je .out
    mov ecx, [mx]
    sub ecx, [esi+WX]
    sub ecx, 6
    mov edx, [my]
    sub edx, [esi+WY]
    sub edx, 30
    cmp edx, CANH
    jae .swatch
    cmp ecx, CANW-3
    jae .out
    cmp edx, CANH-3
    jae .out
    mov ebx, [pcolor]
    mov ebp, 3
.py:
    imul edi, edx, CANW
    add edi, ecx
    lea edi, [CANVAS+edi*4]
    mov [edi], ebx
    mov [edi+4], ebx
    mov [edi+8], ebx
    inc edx
    dec ebp
    jnz .py
.out:
    ret
.swatch:
    sub edx, CANH+6
    cmp edx, 24
    jae .out
    mov eax, ecx
    xor edx, edx
    mov ebx, 30
    div ebx
    cmp eax, 6
    jae .out
    mov eax, [swatches+eax*4]
    mov [pcolor], eax
    ret

press:
    cmp dword [menu], 0
    je .nomenu
    mov dword [menu], 0
    mov eax, [mx]
    cmp eax, 230
    jae .nomenu
    mov eax, [my]
    sub eax, BARY-240+60
    cmp eax, 180
    jae .nomenu
    xor edx, edx
    mov ebx, 45
    div ebx
    cmp eax, 3
    je shutdown
    call open
    ret
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
    xor edx, edx
    mov ebx, 150
    div ebx
    cmp eax, 3
    jae .ret
    call open
.ret:
    ret
.wins:
    mov ecx, 2
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
    cmp edi, 26
    jae .ret
    mov eax, [esi+WW]
    sub eax, 28
    cmp edx, eax
    jb .grab
    mov dword [esi+WVIS], 0
    ret
.grab:
    mov [drag], ebx
    mov [dragx], edx
    mov [dragy], edi
    ret
.next:
    dec ecx
    jns .w
    cmp dword [mx], 96
    jae .ret
    mov eax, [my]
    sub eax, 24
    cmp eax, 3*96
    jae .ret
    xor edx, edx
    mov ebx, 96
    div ebx
    call open
    ret

open:
    push eax
    imul eax, WSIZE
    mov dword [wins+eax+WVIS], 1
    pop eax
    call raise
    ret

raise:
    pushad
    xor ecx, ecx
.f:
    cmp [zord+ecx], al
    je .s
    inc ecx
    cmp ecx, 2
    jb .f
.s:
    cmp ecx, 2
    jae .e
    mov bl, [zord+ecx+1]
    mov [zord+ecx], bl
    inc ecx
    jmp .s
.e:
    mov [zord+2], al
    popad
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
    cmp al, 0x2A
    je .sd
    cmp al, 0x36
    je .sd
    cmp al, 0xAA
    je .su
    cmp al, 0xB6
    je .su
    test al, 0x80
    jnz .out
    movzx ebx, byte [zord+2]
    cmp ebx, 1
    jne .out
    cmp dword [wins+WSIZE+WVIS], 0
    je .out
    mov ecx, [notelen]
    cmp al, 0x0E
    je .bs
    cmp al, 0x1C
    je .nl
    cmp al, 0x39
    ja .out
    movzx eax, al
    mov al, [keymap+eax]
    test al, al
    jz .out
    cmp dword [shift], 0
    je .put
    cmp al, 'a'
    jb .put
    cmp al, 'z'
    ja .put
    sub al, 32
.put:
    cmp ecx, 900
    jae .out
    mov [note+ecx], al
    inc dword [notelen]
    jmp .dirty
.nl:
    mov al, 10
    jmp .put
.bs:
    test ecx, ecx
    jz .out
    dec dword [notelen]
.dirty:
    mov dword [dirty], 1
.out:
    ret
.sd:
    mov dword [shift], 1
    ret
.su:
    mov dword [shift], 0
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

;half
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
    shr eax, 1
    and eax, 0x7F7F7F
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
    mov eax, [g_x]
    mov ebx, [g_y]
    add ebx, ebp
    mov ecx, [g_w]
    mov edx, 1
    call rect
    inc ebp
    jmp .l
.x:
    popad
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

text:
    pushad
.n:
    movzx ecx, byte [esi]
    test ecx, ecx
    jz .x
    call glyph
    add eax, 8
    inc esi
    jmp .n
.x:
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
    mov eax, ebp
    cmp ebp, 600
    jl .s1
    mov eax, 0xFF8A5C
    jmp .s2
.s1:
    call lerp
.s2:
    mov ecx, WIDTH
    rep stosd
    inc ebp
    cmp ebp, HEIGHT
    jl .sky

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
    add eax, 8
    add ebx, 8
    call shade
    sub eax, 8
    sub ebx, 8
    mov esi, 0x20243A
    call rect
    inc eax
    inc ebx
    sub ecx, 2
    sub edx, 2
    mov esi, 0xF4F2EE
    call rect
    movzx edi, byte [zord+2]
    cmp edi, ebp
    jne .inact
    mov esi, 0x2F6BFF
    mov edi, 0x7A3CF0
    jmp .tb
.inact:
    mov esi, 0x8C90A4
    mov edi, 0x6C7088
.tb:
    mov edx, 26
    call grad
    mov esi, [cur]
    mov edx, 0xFFFFFF
    add eax, 10
    add ebx, 5
    mov esi, [esi+WTITLE]
    call text
    mov esi, [cur]
    mov eax, [esi+WX]
    add eax, [esi+WW]
    sub eax, 26
    mov ebx, [esi+WY]
    add ebx, 4
    mov ecx, 20
    mov edx, 19
    mov esi, 0xE5484D
    call rect
    add eax, 6
    add ebx, 1
    mov ecx, 'x'
    mov edx, 0xFFFFFF
    call glyph
    mov esi, [cur]
    mov eax, [esi+WX]
    add eax, 6
    mov ebx, [esi+WY]
    add ebx, 30
    cmp ebp, 0
    je .sys
    cmp ebp, 1
    je .note
    call paint
    jmp .x
.sys:
    mov esi, sysinfo
    mov edx, 0x20243A
.line:
    cmp byte [esi], 0
    je .x
    call text
    add ebx, 20
.skip:
    lodsb
    test al, al
    jnz .skip
    mov eax, [cur]
    mov eax, [eax+WX]
    add eax, 6
    jmp .line
.note:
    call notes
.x:
    popad
    ret

notes:
    pushad
    mov [t_x], eax
    mov [t_y], ebx
    xor esi, esi
    mov edx, 0x20243A
    xor ebp, ebp
.c:
    cmp esi, [notelen]
    jae .caret
    movzx ecx, byte [note+esi]
    inc esi
    cmp cl, 10
    je .nl
    call glyph
    add eax, 8
    inc ebp
    cmp ebp, 52
    jb .c
.nl:
    mov eax, [t_x]
    add ebx, 18
    xor ebp, ebp
    jmp .c
.caret:
    mov ecx, '_'
    call glyph
    popad
    ret

paint:
    pushad
    mov [t_x], eax
    mov [t_y], ebx
    mov ebp, CANH
    mov esi, CANVAS
    mov edx, ebx
.r:
    cmp edx, HEIGHT
    jae .n
    mov ecx, [t_x]
    xor ebx, ebx
.p:
    cmp ecx, WIDTH
    jae .q
    imul edi, edx, WIDTH
    add edi, ecx
    mov eax, [esi+ebx*4]
    mov [BACK+edi*4], eax
.q:
    inc ecx
    inc ebx
    cmp ebx, CANW
    jb .p
.n:
    add esi, CANW*4
    inc edx
    dec ebp
    jnz .r
    xor ebp, ebp
.sw:
    mov eax, ebp
    imul eax, 30
    add eax, [t_x]
    mov ebx, [t_y]
    add ebx, CANH+6
    mov ecx, 26
    mov edx, 24
    mov esi, [swatches+ebp*4]
    call rect
    inc ebp
    cmp ebp, 6
    jb .sw
    popad
    ret

icons:
    xor ebp, ebp
.i:
    mov eax, 24
    imul ebx, ebp, 96
    add ebx, 28
    mov ecx, 48
    mov edx, 48
    mov esi, [iconc+ebp*8]
    mov edi, [iconc+ebp*8+4]
    call grad
    mov eax, 12
    add ebx, 54
    mov esi, [titles+ebp*4]
    mov edx, 0x000000
    inc eax
    inc ebx
    call text
    dec eax
    dec ebx
    mov edx, 0xFFFFFF
    call text
    inc ebp
    cmp ebp, 3
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
    call grad
    add eax, 24
    add ebx, 6
    mov esi, s_start
    mov edx, 0xFFFFFF
    call text
    xor ebp, ebp
.t:
    imul edx, ebp, WSIZE
    cmp dword [wins+edx+WVIS], 0
    je .n
    imul eax, ebp, 150
    add eax, 112
    mov ebx, BARY+6
    mov ecx, 142
    mov edx, 28
    mov esi, 0x3C4270
    movzx edi, byte [zord+2]
    cmp edi, ebp
    jne .tb
    mov esi, 0x5A63A8
.tb:
    call rect
    add eax, 10
    add ebx, 6
    mov esi, [titles+ebp*4]
    mov edx, 0xFFFFFF
    call text
.n:
    inc ebp
    cmp ebp, 3
    jb .t
    mov eax, WIDTH-60
    mov ebx, BARY+12
    mov esi, clock
    mov edx, 0xFFFFFF
    call text
    ret

startmenu:
    cmp dword [menu], 0
    je .x
    mov eax, 0
    mov ebx, BARY-240
    mov ecx, 230
    mov edx, 240
    mov esi, 0xF4F2EE
    call rect
    mov edx, 60
    mov esi, 0x2F6BFF
    mov edi, 0x7A3CF0
    call grad
    add eax, 16
    add ebx, 22
    mov esi, s_name
    mov edx, 0xFFFFFF
    call text
    xor ebp, ebp
.i:
    imul ebx, ebp, 45
    add ebx, BARY-240+60
    mov eax, [my]
    sub eax, ebx
    cmp eax, 45
    jae .nh
    cmp dword [mx], 230
    jae .nh
    xor eax, eax
    mov ecx, 230
    mov edx, 45
    mov esi, 0xCFD8FF
    call rect
.nh:
    mov eax, 20
    add ebx, 14
    mov esi, [titles+ebp*4]
    mov edx, 0x20243A
    call text
    inc ebp
    cmp ebp, 4
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
    cmp ecx, 3
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
shift   dd 0
lastmin dd 99
notelen dd 0
pcolor  dd 0x20243A
cur     dd 0
t_x     dd 0
t_y     dd 0
g_x     dd 0
g_y     dd 0
g_w     dd 0
g_h     dd 1
g_c1    dd 0
g_c2    dd 0

zord    db 1, 2, 0, 0
clock   db '00:00', 0

wins:
    dd 150, 70, 440, 230, 1, s_sys, 0
    dd 300, 170, 440, 300, 0, s_note, 0
    dd 420, 90, 434, 346, 0, s_paint, 0

titles  dd s_sys, s_note, s_paint, s_off
iconc   dd 0x2F6BFF, 0x7A3CF0, 0xFFC24B, 0xF0802A, 0x35C98A, 0x128A5A
swatches dd 0x20243A, 0xE5484D, 0xF0A020, 0x35C98A, 0x2F6BFF, 0xFFFFFF

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
s_note  db 'Notepad', 0
s_paint db 'Paint', 0
s_off   db 'Shut down', 0
s_start db 'Start', 0
s_name  db 'XD OS', 0

sysinfo:
    db 'XD OS', 0
    db 'Hand-written x86 assembly', 0
    db '1024 x 768, 32-bit colour', 0
    db 'Windows, mouse, keyboard, clock', 0
    db 'The whole system fits in 65,536 bytes', 0
    db 0

keymap:
    db 0, 0, '1234567890-=', 0, 0
    db 'qwertyuiop[]', 0, 0
    db 'asdfghjkl;', 39, '`', 0, '\'
    db 'zxcvbnm,./', 0, '*', 0, ' '

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

note:
    times 1000 db 0

code_end:
times 65536-($-$$) db 0
