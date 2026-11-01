FLW     equ 320
FLH     equ 360
GROUND  equ 322
PIPEW   equ 54
GAP     equ 118	; pipe gap
BIRDX   equ 80
BIRDW   equ 28
BIRDH   equ 22
HLW     equ 480
HLH     equ 300
CARA    equ 100
CARB    equ 150

flap_gap:
    call rand
    xor edx, edx
    mov ecx, 170
    div ecx
    lea eax, [edx+36]
    ret

flap_reset:
    mov dword [fl_y], 150<<8
    mov dword [fl_v], 0
    mov dword [fl_score], 0
    mov dword [fl_state], 0
    mov dword [fl_px], 340
    mov dword [fl_px+4], 520
    mov dword [fl_px+8], 700
    call flap_gap
    mov [fl_gy], eax
    call flap_gap
    mov [fl_gy+4], eax
    call flap_gap
    mov [fl_gy+8], eax
    ret

; flap or restart
flap_up:
    cmp dword [fl_state], 2
    jne .go
    call flap_reset
    mov dword [dirty], 1
    ret
.go:
    mov dword [fl_state], 1
    mov dword [fl_v], -1340
    ret

click_flap:
    call flap_up
    ret

key_flap:
    cmp al, ' '
    jne .x
    call flap_up
.x:
    ret

flap_tick:
    cmp dword [fl_state], 1
    jne .x
    add dword [fl_v], 56	;gravity (8.8 fixed)
    mov eax, [fl_v]
    add [fl_y], eax
    xor ecx, ecx
.p:
    mov eax, [fl_px+ecx*4]
    lea ebx, [eax+PIPEW]
    sub eax, 3
    mov [fl_px+ecx*4], eax
    cmp ebx, BIRDX
    jl .np
    lea ebx, [eax+PIPEW]
    cmp ebx, BIRDX
    jge .np
    inc dword [fl_score]
.np:
    cmp eax, -PIPEW
    jg .n
    add dword [fl_px+ecx*4], 540
    call flap_gap
    mov [fl_gy+ecx*4], eax
.n:
    inc ecx
    cmp ecx, 3
    jb .p
    mov ebx, [fl_y]
    sar ebx, 8
    cmp ebx, 0
    jl .dead
    lea eax, [ebx+BIRDH]
    cmp eax, GROUND
    jge .dead
    xor ecx, ecx
.c:
    mov eax, [fl_px+ecx*4]
    cmp eax, BIRDX+BIRDW
    jge .cn
    add eax, PIPEW
    cmp eax, BIRDX
    jle .cn
    mov eax, [fl_gy+ecx*4]
    cmp ebx, eax
    jl .dead
    add eax, GAP
    lea edx, [ebx+BIRDH]
    cmp edx, eax
    jg .dead
.cn:
    inc ecx
    cmp ecx, 3
    jb .c
    jmp .d
.dead:
    mov dword [fl_state], 2
.d:
    mov dword [gdirty], 1
.x:
    ret

draw_flap:
    pushad
    mov eax, [cx0]
    mov ebx, [cy0]
    mov ecx, FLW
    mov edx, GROUND
    mov esi, 0x1B2A6C
    mov edi, 0xF09A6A
    call grad
    xor ebp, ebp
.p:
    mov eax, [fl_px+ebp*4]
    lea ecx, [eax+PIPEW]
    cmp eax, 0
    jge .l
    xor eax, eax
.l:
    cmp ecx, FLW
    jle .r
    mov ecx, FLW
.r:
    sub ecx, eax
    cmp ecx, 0
    jle .n
    add eax, [cx0]
    mov ebx, [cy0]
    mov edx, [fl_gy+ebp*4]
    mov esi, 0x2BAE66
    call rect
    mov ebx, [fl_gy+ebp*4]
    add ebx, GAP
    mov edx, GROUND
    sub edx, ebx
    add ebx, [cy0]
    call rect
.n:
    inc ebp
    cmp ebp, 3
    jb .p
    mov eax, [cx0]
    mov ebx, [cy0]
    add ebx, GROUND
    mov ecx, FLW
    mov edx, FLH-GROUND
    mov esi, 0x5A3A22
    mov edi, 0x2C1A10
    call grad
    mov eax, [cx0]
    add eax, BIRDX
    mov ebx, [fl_y]
    sar ebx, 8
    add ebx, [cy0]
    mov ecx, BIRDW
    mov edx, BIRDH
    mov esi, 0xFFC24B
    mov edi, 0xF0802A
    call rgrad
    add eax, 18
    add ebx, 5
    mov ecx, 5
    mov edx, 5
    mov esi, 0x20243A
    call rect
    mov eax, [fl_score]
    call itoa
    mov eax, [cx0]
    add eax, 12
    mov ebx, [cy0]
    add ebx, 8
    mov edx, 0xFFFFFF
    call text
    mov esi, s_fl0
    cmp dword [fl_state], 0
    je .m
    mov esi, s_fl2
    cmp dword [fl_state], 2
    jne .x
.m:
    call twidth
    shr eax, 1
    neg eax
    add eax, FLW/2
    add eax, [cx0]
    mov ebx, [cy0]
    add ebx, 150
    mov edx, 0xFFFFFF
    call text
.x:
    popad
    ret

hill_init:
    mov esi, hl_wave
    xor ecx, ecx
.l:
    call wave
    mov [HILLT+ecx*4], eax
    inc ecx
    cmp ecx, 4096
    jb .l
    ret

hill_at:
    and eax, 4095
    mov eax, [HILLT+eax*4]
    ret

;slope pushes the car. right/d gas, left/a brake
hill_tick:
    mov ecx, [hl_pos]
    sar ecx, 8
    lea eax, [ecx+CARB]
    call hill_at
    mov ebx, eax
    lea eax, [ecx+CARA]
    call hill_at
    sub ebx, eax
    mov edx, [hl_vel]
    sar ebx, 1
    add edx, ebx
    cmp byte [keys+0x4D], 0
    jne .gas
    cmp byte [keys+0x20], 0
    je .nogas
.gas:
    add edx, 44
.nogas:
    cmp byte [keys+0x4B], 0
    jne .brk
    cmp byte [keys+0x1E], 0
    je .nobrk
.brk:
    sub edx, 44
.nobrk:
    mov eax, edx
    sar eax, 5
    sub edx, eax
    cmp edx, 1400
    jle .a
    mov edx, 1400
.a:
    cmp edx, -1400
    jge .b
    mov edx, -1400
.b:
    mov [hl_vel], edx
    add [hl_pos], edx
    cmp dword [hl_pos], 0
    jge .c
    mov dword [hl_pos], 0
    mov dword [hl_vel], 0
.c:
    cmp edx, 0
    je .x
    mov dword [gdirty], 1
.x:
    ret

draw_hill:
    pushad
    mov eax, [cx0]
    mov ebx, [cy0]
    mov ecx, HLW
    mov edx, HLH
    mov esi, 0x2F6BFF
    mov edi, 0xCFE8FF
    call grad
    mov ebp, [hl_pos]
    sar ebp, 8
    xor ecx, ecx
.col:
    lea eax, [ebp+ecx]
    call hill_at
    mov ebx, eax
    push ecx
    lea eax, [ecx]
    add eax, [cx0]
    mov edx, HLH
    sub edx, ebx
    add ebx, [cy0]
    mov ecx, 1
    mov esi, 0x4C8C3A
    call rect
    mov edx, 4
    mov esi, 0x8BD45A
    call rect
    pop ecx
    inc ecx
    cmp ecx, HLW
    jb .col

    lea eax, [ebp+CARA]
    call hill_at
    mov [hl_ya], eax
    lea eax, [ebp+CARB]
    call hill_at
    mov [hl_yb], eax
    xor ecx, ecx
.car:
    mov eax, [hl_yb]
    sub eax, [hl_ya]
    imul eax, ecx
    cdq
    mov ebx, 66
    idiv ebx
    add eax, [hl_ya]
    mov ebx, eax
    sub ebx, 28
    add ebx, [cy0]
    push ecx
    lea eax, [ecx+CARA-8]
    add eax, [cx0]
    mov edx, 16
    mov esi, 0xE5484D
    cmp dword [esp], 16
    jb .body
    cmp dword [esp], 46
    jae .body
    sub ebx, 12
    add edx, 12
.body:
    mov ecx, 1
    call rect
    pop ecx
    inc ecx
    cmp ecx, 66
    jb .car

    mov eax, [cx0]
    add eax, CARA-9
    mov ebx, [hl_ya]
    add ebx, [cy0]
    sub ebx, 16
    mov ecx, 18
    mov edx, 18
    mov esi, 0x20243A
    call rbox
    mov eax, [cx0]
    add eax, CARB-9
    mov ebx, [hl_yb]
    add ebx, [cy0]
    sub ebx, 16
    call rbox

    mov eax, ebp
    xor edx, edx
    mov ebx, 10
    div ebx
    call itoa
    mov eax, [cx0]
    add eax, 12
    mov ebx, [cy0]
    add ebx, 8
    mov edx, 0x20243A
    call text
    call twidth
    add eax, [cx0]
    add eax, 16
    mov esi, s_m
    call text
    mov esi, s_hl
    mov eax, [cx0]
    add eax, 300
    call text
    popad
    ret

fl_y     dd 0
fl_v     dd 0
fl_score dd 0
fl_state dd 0
fl_px    dd 0, 0, 0
fl_gy    dd 0, 0, 0
hl_pos   dd 0
hl_vel   dd 0
hl_ya    dd 0
hl_yb    dd 0
hl_wave  dd 190
         dd 0.00460194, 52.0, 0.01687379, 24.0
s_fl0    db 'Click or press Space', 0
s_fl2    db 'Crashed. Click to retry', 0
s_m      db 'm', 0
s_hl     db 'Hold Right arrow to drive', 0
