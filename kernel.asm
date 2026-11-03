%include "defs.inc"
bits 32
org KERNEL

    ;boot sector jumps here
    call sys_init
    fninit
    cld
    call mouse_init
    call font_init
    call wallpaper
    mov edi, CANVAS
    mov ecx, CANW*CANH
    mov eax, 0xFFFFFF
    rep stosd
    call browser_init
    call term_init
    mov dword [dirty], 1

main:
    call poll
    call clock_tick
    call vm_tick
    cmp dword [dirty], 0
    jne .full
    ; only the game changed
    cmp dword [gdirty], 0
    je main
    and dword [gdirty], 0
    call fastframe
    jmp main
.full:
    and dword [dirty], 0
    and dword [gdirty], 0
    call scene
    cmp dword [b_go], 0
    je main
    call browser_go
    jmp main

fastframe:
    movzx ebp, byte [zord+NWIN-1]
    imul eax, ebp, WSIZE
    lea esi, [wins+eax]
    mov [cur], esi
    mov eax, [esi+WX]
    add eax, 6
    mov [cx0], eax
    mov ebx, [esi+WY]
    add ebx, 30
    mov [cy0], ebx
    mov ecx, [esi+WW]
    sub ecx, 12
    mov edx, [esi+WH]
    sub edx, 36
    pushad
    call [appdraw+ebp*4]
    call cursor
    popad
    lea edi, [ebx+edx]
    cmp edi, BARY
    jle blit
    mov edx, BARY
    sub edx, ebx

blit:
    call clip
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

;base + a*sin(x*f) + b*sin(x*g)
wave:
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
    mov eax, [t_y]
    ret

; al=key edi=buf ebx=len ecx=max, cf=nothing changed
edit_key:
    test al, al
    jz .no
    mov edx, [ebx]
    cmp al, 8
    jne .add
    test edx, edx
    jz .no
    dec edx
    jmp .st
.add:
    cmp edx, ecx
    jae .no
    mov [edi+edx], al
    inc edx
.st:
    mov [ebx], edx
    mov byte [edi+edx], 0
    clc
    ret
.no:
    stc
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
    and dword [midx], 0
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
    and dword [mx], 0
.a:
    cmp dword [mx], WIDTH-1
    jle .b
    mov dword [mx], WIDTH-1
.b:
    cmp dword [my], 0
    jge .c
    and dword [my], 0
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
    or dword [drag], -1
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
    and dword [menu], 0
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
    jns .bn
    cmp al, [zord+NWIN-1]
    jne open
    cmp dword [wins+ebx+WVIS], 1
    jne open
    lea esi, [wins+ebx]
    jmp minimize
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
    cmp dword [esi+WVIS], 1
    jne .next
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
    jb .notx
    and dword [esi+WVIS], 0
    ret
.notx:
    sub eax, 22
    cmp edx, eax
    jae .max
    sub eax, 22
    cmp edx, eax
    jae minimize
    cmp dword [esi+WMAX], 0
    jne .ret
    mov [drag], ebx
    mov [dragx], edx
    mov [dragy], edi
    ret
.max:
    mov edi, ebx
    shl edi, 4
    add edi, WSAVE
    xor dword [esi+WMAX], 1
    jz .back
    push esi
    mov ecx, 4
    rep movsd
    pop esi
    and dword [esi+WX], 0
    and dword [esi+WY], 0
    mov dword [esi+WW], WIDTH
    mov dword [esi+WH], BARY
    jmp .sized
.back:
    xchg esi, edi
    mov ecx, 4
    rep movsd
.sized:
    cmp ebx, A_BROWSE
    je browser_resize
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

minimize:
    mov dword [esi+WVIS], 2
    mov al, [zord+NWIN-1]
    mov ecx, NWIN-1
.l:
    mov ah, [zord+ecx-1]
    mov [zord+ecx], ah
    loop .l
    mov [zord], al
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
    mov [lastscan], al                  ;games read this
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
    cmp dword [wins+edx+WVIS], 1
    jne .out
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
    mov ah, [edi]
    test al, al
    jz .e
    or ax, 0x2020
.e:
    cmp al, ah
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

; le=nothing to draw
clip:
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
    imul edi, ebx, WIDTH
    add edi, eax
    lea edi, [BACK+edi*4]
    cmp ecx, 0
    jle .x
    cmp edx, 0
.x:
    ret

rect:
    pushad
    call clip
    jle .x
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
    call clip
    jle .x
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
    call rgrad
    pop edi
    ret

rgrad:
    mov dword [g_round], 2
    call grad
    and dword [g_round], 0
    ret

; ebp 1=48px, 2=24px
cicon:
    pushad
    mov ecx, 48
    cmp ebp, 1
    je .t
    shr ecx, 1
.t:
    mov edx, ecx
    mov esi, [iconc+edi*4]
    push edi
    mov edi, esi
    shr edi, 1
    and edi, 0x7F7F7F
    call rgrad
    pop edi
    shl edi, 5
    add edi, iconbits
    mov esi, 8
    cmp ebp, 1
    je .o
    shr esi, 1
.o:
    add eax, esi
    add ebx, esi
    neg ebp
    add ebp, 3
    mov ecx, 16
.row:
    push ecx
    push eax
    mov dx, [edi]
    add edi, 2
    mov ecx, 16
.col:
    shl dx, 1
    jnc .n
    pushad
    mov ecx, ebp
    mov edx, ebp
    mov esi, 0xFFFFFF
    call rect
    popad
.n:
    add eax, ebp
    loop .col
    pop eax
    pop ecx
    add ebx, ebp
    loop .row
    popad
    ret

;make the bios font proportional
font_init:
    mov esi, FONT
    xor edi, edi
.c:
    xor ebx, ebx
    mov ecx, 16
.o:
    lodsb
    or bl, al
    loop .o
    mov eax, 0x0400
    test bl, bl
    jz .s
    bsr ecx, ebx
    bsf edx, ebx
    mov al, 7
    sub al, cl
    mov ah, cl
    sub ah, dl
    add ah, 2
.s:
    mov [FW+edi*2], ax
    inc edi
    cmp edi, 256
    jb .c
    ret

text:
    pushad
.n:
    movzx ecx, byte [esi]
    jecxz .x
    movzx edi, byte [FW+ecx*2]
    sub eax, edi
    call glyph
    add eax, edi
    movzx edi, byte [FW+ecx*2+1]
    add eax, edi
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
    jecxz .x
    movzx ecx, byte [FW+ecx*2+1]
    add eax, ecx
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
    call wave
    mov ebx, eax
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
    cmp dword [esi+WVIS], 1
    jne .x
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
    and dword [g_round], 0
    mov esi, [cur]
    mov edx, 0xFFFFFF
    add eax, 10
    add ebx, 4
    mov esi, [esi+WTITLE]
    call text
    mov eax, 27
    mov ecx, 'x'
    mov esi, 0xE5484D
    call tbtn
    mov eax, 49
    mov ecx, 0xFE
    mov esi, 0x5A63A8
    call tbtn
    mov eax, 71
    mov cl, '_'
    call tbtn
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

tbtn:
    pushad
    mov edi, [cur]
    neg eax
    add eax, [edi+WX]
    add eax, [edi+WW]
    mov ebx, [edi+WY]
    add ebx, 5
    push ecx
    mov ecx, 20
    mov edx, 18
    call rbox
    add eax, 6
    pop ecx
    mov edx, 0xFFFFFF
    call glyph
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
    and dword [t_y], 0
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
    xor eax, eax
    xor ebx, ebx
    mov ecx, WIDTH
    mov edx, HEIGHT
    jmp blit

%include "fs.inc"
%include "apps.inc"
%include "vm.inc"
%include "net.inc"
%include "browser.inc"

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
    dd 200, 70, 652, 436, 0, s_flap, 0
    dd 240, 110, 652, 436, 0, s_hill, 0
    dd 420, 90, 434, 346, 0, s_paint, 0
    dd 140, 40, 740, 560, 0, s_browse, 0

titles  dd s_sys, s_term, s_note, s_files, s_calc, s_flap, s_hill, s_paint, s_browse, s_off
appdraw dd draw_sys, draw_term, draw_note, draw_files, draw_calc, draw_vm, draw_vm, draw_paint, draw_browser
appclick dd nop_app, nop_app, click_note, click_files, click_calc, click_vm, click_vm, nop_app, click_browser
appkey  dd nop_app, key_term, key_note, nop_app, nop_app, key_vm, key_vm, nop_app, key_browser

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
s_flap  db 'flappy.img', 0
s_hill  db 'hill1k.img', 0
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

iconc   dd 0x2F6BFF, 0x2A2F52, 0xF0A020, 0xE0A020, 0x3A8FE0, 0xF0C040, 0x3AA0E0, 0xD06030, 0xC04A90
%include "icons.inc"

