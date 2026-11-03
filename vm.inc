; v86 stuff for the games
PD      equ 0x2700000
PDV     equ 0x2701000  ;pd for the game
PT      equ 0x2702000
IDT     equ 0x2703000
BASEPAL equ 0x2704000
VPAL    equ 0x2704400               ; game palette
FW      equ 0x2704800                   ;glyph offset/width
KSTACK  equ 0x27E0000
VSTACK  equ 0x27F0000
VMBASE  equ 0x2800000 ;  game's 1mb
VGA     equ VMBASE+0xA0000
FONT8   equ FONT+0x1000
V_ESI   equ 4
V_EBX   equ 16
V_EDX   equ 20
V_ECX   equ 24
V_EAX   equ 28
V_EIP   equ 32
V_CS    equ 36
V_FL    equ 40
V_SP    equ 44

sys_init:
    cli
    pop ebx
    mov esp, KSTACK
    push ebx
    mov edi, PD
    ; 4mb pages,identity
    mov eax, 0x83
    mov ecx, 1024
.pd:
    stosd
    add eax, 0x400000
    loop .pd
    ; game pd: low 4mb in 4k pages
    mov esi, PD
    mov edi, PDV
    mov ecx, 1024
    rep movsd
    mov dword [PDV], PT+7
    mov edi, PT
    xor ecx, ecx
.pt:
    mov eax, ecx
    shl eax, 12
    ; first 1mb -> VMBASE
    cmp ecx, 256
    jae .id
    add eax, VMBASE
.id:
    or eax, 7
    stosd
    inc ecx
    cmp ecx, 1024
    jb .pt
  ; pse + paging
    mov eax, cr4
    or eax, 0x10
    mov cr4, eax
    mov eax, PD
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax

    mov eax, tss
    mov [kgdt+0x18+2], ax
    shr eax, 16
    mov [kgdt+0x18+4], al
    mov [kgdt+0x18+7], ah
    lgdt [kgdtr]
    mov ax, 0x18
    ltr ax

    mov edi, IDT
    mov ecx, 256
    ; everything -> vm_fault for now
    mov eax, vm_fault
.idt:
    call gate
    loop .idt
    mov edi, IDT+13*8
    mov eax, gp_entry
    call gate
    mov edi, IDT+0x20*8
    mov eax, irq0
    call gate
    lidt [kidtr]

    ; pic remap, only timer
    mov esi, picinit
.pic:
    lodsw
    test ah, ah
    jz .pe
    movzx edx, ah
    out dx, al
    jmp .pic
.pe:
  ; 120hz
    mov al, 0x34
    out 0x43, al
    mov ax, 9943
    out 0x40, al
    mov al, ah
    out 0x40, al

    ; 6 bit dac->32 bit
    mov esi, 0x6800
    mov edi, BASEPAL
    mov ecx, 256
.pal:
    xor eax, eax
    mov ebx, 3
.ch:
    shl eax, 8
    mov dl, [esi]
    inc esi
    shl dl, 2
    mov al, dl
    dec ebx
    jnz .ch
    stosd
    loop .pal
    sti
    ret

gate:
    mov edx, eax
    mov [edi], dx
    mov word [edi+2], 0x08
    mov word [edi+4], 0x8E00
    shr edx, 16
    mov [edi+6], dx
    add edi, 8
    ret

;timer. if we came from v86, leave the game
irq0:
    test dword [esp+8], 0x20000
    jnz .vm
    push eax
    inc dword [ticks]
    mov al, 0x20
    out 0x20, al                    ; eoi
    pop eax
    iretd
.vm:
    pushad
    mov ebp, 2
    lea esi, [esp+32]
    jmp vm_exit

; game crashed? restart it
vm_fault:
    pushad
    mov ebp, 3
    lea esi, [esp+32]
    jmp vm_exit

;  int/in/out/hlt from the game end up here
gp_entry:
    pushad
    mov ebp, 1
    lea esi, [esp+36]

vm_exit:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov eax, PD		;  back to kernel pd
    mov cr3, eax
    mov ebx, esi
    mov esi, esp
    mov edi, vregs
    mov ecx, 8
    rep movsd
    mov esi, ebx
    mov ecx, 9
    rep movsd
    mov [vreason], ebp
    cmp ebp, 2
    jne .k
    inc dword [ticks]
    mov al, 0x20
    out 0x20, al
.k:
    mov esp, [kesp]
    popad
    sti
    ret

vm_enter:
    pushad
    mov [kesp], esp
    cli
    mov eax, PDV
    mov cr3, eax
    mov esi, vregs+16*4
    mov ecx, 17
.p:
    push dword [esi]
    sub esi, 4
    loop .p
    popad
    iretd ; into the game

; load game at 0:7c00 and reset
vm_load:
    mov [vm_app], eax
    cmp eax, A_FLAP
    mov esi, g_flappy
    mov ecx, g_flappy_end-g_flappy
    je .c
    mov esi, g_hill
    mov ecx, g_hill_end-g_hill
.c:
    push ecx
    push esi
    mov edi, VMBASE
    mov ecx, 0x40000
    xor eax, eax
    rep stosd
    mov edi, vregs
    mov ecx, 17
    rep stosd
    pop esi
    pop ecx
    mov edi, VMBASE+0x7C00
    rep movsb
    mov dword [vregs+V_EIP], 0x7C00
    mov dword [vregs+V_SP], 0x7C00
    mov dword [vregs+V_FL], 0x20202
    mov byte [vregs+V_EDX], 0x80 ; dl=80h
    mov esi, BASEPAL
    mov edi, VPAL
    mov ecx, 256
    rep movsd
    mov eax, [ticks]
    mov [vm_done], eax
    and dword [vm_key], 0
    ret

; only runs while on top
vm_tick:
    movzx eax, byte [zord+NWIN-1]
    cmp eax, A_FLAP
    je .ok
    cmp eax, A_HILL
    jne .x
.ok:
    imul ebx, eax, WSIZE
    cmp dword [wins+ebx+WVIS], 1
    jne .x
    cmp eax, [vm_app]
    je .run
    call vm_load
.run:
    mov ecx, [ticks]
    sub ecx, [vm_done]
    jle .x
    ;  max 6 ticks behind
    cmp ecx, 6
    jbe .n
    mov ecx, 6
    mov eax, [ticks]
    sub eax, ecx
    mov [vm_done], eax
.n:
    push ecx
    inc dword [vm_done]
    inc word [VMBASE+0x46C] ; bios tick count 40:6c
    call vm_slice
    pop ecx
    loop .n
    mov eax, [ticks]
    mov ebx, eax
    sub eax, [vm_draw]
    cmp eax, 3   ; redraw every 3 ticks
    jb .x
    mov [vm_draw], ebx
    mov dword [gdirty], 1
.x:
    ret

vm_slice:
    call vm_enter
    mov eax, [vreason]
    cmp eax, 2
    je .x
    cmp eax, 3
    jne .em
    mov eax, [vm_app]
    jmp vm_load
.em:
    call vm_emulate
    jnc vm_slice
.x:
    ret

; what did it fault on?
vm_emulate:
    mov esi, [vregs+V_CS]
    and esi, 0xFFFF
    shl esi, 4
    movzx eax, word [vregs+V_EIP]
    lea esi, [VMBASE+esi+eax]
    movzx eax, byte [esi]
    movzx ebx, byte [esi+1]
    movzx edx, word [vregs+V_EDX]
    cmp al, 0xCD  ; int
    je .int
    cmp al, 0xF4                ; hlt
    je .hlt
    cmp al, 0xE4   ; in al, imm
    je .ini
    cmp al, 0xEC                            ; in al, dx
    je .ind
    cmp al, 0xE6                            ; out imm, al
    je .outi
    cmp al, 0xEE ;out dx, al
    je .outd
.step:
    inc dword [vregs+V_EIP]
    clc
    ret
.hlt:
    inc dword [vregs+V_EIP]
    stc
    ret
.ini:
    inc dword [vregs+V_EIP]
    mov edx, ebx
.ind:
    call vm_in
    mov [vregs+V_EAX], al
    jmp .step
.outi:
    inc dword [vregs+V_EIP]
    mov edx, ebx
.outd:
    call vm_out
    jmp .step
.int:
    add dword [vregs+V_EIP], 2
    movzx eax, word [vregs+V_EAX]
    cmp bl, 0x10
    je vm_int10
    cmp bl, 0x16
    je vm_int16
    clc
    ret

;60h = last key we saw, mouse bytes stay out
vm_in:
    cmp dl, 0x60
    jne .r
    mov al, [lastscan]
    ret
.r:
    in al, 0x40  ;pit
    ret

;palette 3c8/3c9
vm_out:
    mov al, [vregs+V_EAX]
    cmp dx, 0x3C8
    jne .d
    movzx eax, al
    mov [v_pidx], eax
    and dword [v_psub], 0
    ret
.d:
    cmp dx, 0x3C9
    jne .x
    shl al, 2 ; 6->8 bit
    mov ecx, [v_psub]
    mov edx, [v_pidx]
    neg ecx
    add ecx, 2
    mov [VPAL+edx*4+ecx], al
    inc dword [v_psub]
    cmp dword [v_psub], 3
    jb .x
    and dword [v_psub], 0
    inc byte [v_pidx]
.x:
    ret

;int 16h. ah=0 wait, ah=1 peek
vm_int16:
    test ah, ah
    jz .read
    and dword [vregs+V_FL], ~0x40
    cmp dword [vm_key], 0
    jne .ok
    or dword [vregs+V_FL], 0x40
.ok:
    clc
    ret
.read:
    cmp dword [vm_key], 0
    jne .got
    sub dword [vregs+V_EIP], 2   ; no key, retry the int
    stc
    ret
.got:
    and dword [vm_key], 0
    clc
    ret

vm_int10:
    movzx ebx, byte [vregs+V_EBX]
    cmp ah, 2
    je .cur
    cmp ah, 0x0E
    je .tty
    cmp ah, 9
    je .rep
    clc
    ret
.cur:
    mov ax, [vregs+V_EDX]
    mov [v_cur], ax
    clc
    ret
.tty:
    call vm_putc
    inc byte [v_cur]
    clc
    ret
.rep:
    movzx ecx, word [vregs+V_ECX]
    mov dl, [v_cur]
    jecxz .e
.r:
    push ecx
    call vm_putc
    pop ecx
    inc byte [v_cur]
    loop .r
.e:
    mov [v_cur], dl
    clc
    ret

;char al,color bl,8x8 font
vm_putc:
    pushad
    movzx esi, al
    shl esi, 3
    add esi, FONT8
    movzx edi, byte [v_cur+1]
    imul edi, 320*8
    movzx eax, byte [v_cur]
    lea edi, [edi+eax*8+VGA]
    mov edx, 8
.y:
    lodsb
    mov ecx, 8
.x:
    xor ah, ah
    shl al, 1
    jnc .p
    mov ah, bl
.p:
    mov [edi], ah
    inc edi
    loop .x
    add edi, 320-8
    dec edx
    jnz .y
    popad
    ret

key_vm:
click_vm:
    mov dword [vm_key], 1
    ret

; integer scale 320x200 into the window
draw_vm:
    pushad
    mov edi, [cur]
    mov ecx, [edi+WW]
    sub ecx, 12
    mov edx, [edi+WH]
    sub edx, 36
    mov [v_cw], ecx
    mov [v_ch], edx
    mov eax, [cx0]
    mov ebx, [cy0]
    xor esi, esi
    call rect
    xchg eax, ecx
    xor edx, edx
    mov ebx, 320
    div ebx
    xchg ecx, eax
    mov eax, [v_ch]
    xor edx, edx
    mov ebx, 200
    div ebx
    cmp eax, ecx
    jbe .m
    mov eax, ecx
.m:
    xchg ebp, eax
    mov eax, 0x10000
    xor edx, edx
    div ebp
    inc eax
    mov [v_inv], eax
    imul ecx, ebp, 320
    imul edx, ebp, 200
    mov eax, [v_cw]
    sub eax, ecx
    shr eax, 1
    add eax, [cx0]
    mov ebx, [v_ch]
    sub ebx, edx
    shr ebx, 1
    add ebx, [cy0]
    mov [v_cw], eax
    mov [v_ch], ebx
    call clip
    jle .x
    mov esi, eax
    sub esi, [v_cw]
    imul esi, [v_inv]
    mov ebp, ebx
    sub ebp, [v_ch]
    imul ebp, [v_inv]
.row:
    push ecx
    push esi
    push edi
    mov eax, ebp
    shr eax, 16
    imul eax, 320
    add eax, VGA
.px:
    mov ebx, esi
    shr ebx, 16
    movzx ebx, byte [eax+ebx]
    mov ebx, [VPAL+ebx*4]
    mov [edi], ebx
    add edi, 4
    add esi, [v_inv]
    dec ecx
    jnz .px
    pop edi
    pop esi
    pop ecx
    add edi, WIDTH*4
    add ebp, [v_inv]
    dec edx
    jnz .row
.x:
    popad
    ret

ticks    dd 0
v_cw     dd 0
v_ch     dd 0
v_inv    dd 0
vm_app   dd -1
vm_done  dd 0
vm_draw  dd 0
vm_key   dd 0
vreason  dd 0
kesp     dd 0
v_pidx   dd 0
v_psub   dd 0
v_cur    dw 0
lastscan db 0
vregs    times 17 dd 0
;val, port
picinit:
    db 0x11, 0x20, 0x11, 0xA0, 0x20, 0x21, 0x28, 0xA1, 4, 0x21, 2, 0xA1, 1, 0x21, 1, 0xA1, 0xFE, 0x21, 0xFF, 0xA1, 0, 0
kgdt:
    dq 0
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
    dq 0x0000890000000067
kgdtr:
    dw 31
    dd kgdt
kidtr:
    dw 256*8-1
    dd IDT
tss:
    dd 0, VSTACK, 0x10
    times 23 dd 0
g_flappy:
    incbin "games/flappy.img"
g_flappy_end:
g_hill:
    incbin "games/hill1k.img"
g_hill_end:
