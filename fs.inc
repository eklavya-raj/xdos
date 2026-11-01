ata_wait:
    mov dx, 0x1F7
.b:
    in al, dx
    test al, 0x80
    jnz .b
    ret

;pio,writes straight into the image
ata_write:
    pushad
    mov ebx, eax
    mov ebp, ecx
.s:
    call ata_wait
    mov dx, 0x1F6
    mov eax, ebx
    shr eax, 24
    and al, 0x0F
    or al, 0xE0
    out dx, al
    mov dx, 0x1F2
    mov al, 1
    out dx, al
    mov dx, 0x1F3
    mov al, bl
    out dx, al
    mov dx, 0x1F4
    mov al, bh
    out dx, al
    mov dx, 0x1F5
    mov eax, ebx
    shr eax, 16
    out dx, al
    mov dx, 0x1F7
    mov al, 0x30
    out dx, al
.d:
    in al, dx
    test al, 0x80
    jnz .d
    test al, 8
    jz .d
    mov dx, 0x1F0
    mov ecx, 256
    rep outsw
    call ata_wait
    mov dx, 0x1F7
    mov al, 0xE7
    out dx, al
    call ata_wait
    inc ebx
    dec ebp
    jnz .s
    popad
    ret

fs_savedir:
    pushad
    mov eax, FSLBA
    mov ecx, 1
    mov esi, FSMEM
    call ata_write
    popad
    ret

fs_entry:
    shl eax, 5
    add eax, FSMEM
    ret

fs_data:
    shl eax, 10
    add eax, FSMEM+512
    ret

; -1 if not found
fs_find:
    push ebx
    push edi
    xor ebx, ebx
.l:
    mov eax, ebx
    call fs_entry
    mov edi, eax
    cmp dword [edi+28], 0
    je .n
    call strcmp
    je .f
.n:
    inc ebx
    cmp ebx, FSMAX
    jb .l
    mov eax, -1
    jmp .x
.f:
    mov eax, ebx
.x:
    pop edi
    pop ebx
    ret

fs_create:
    push ebx
    push ecx
    push esi
    push edi
    xor ebx, ebx
.l:
    mov eax, ebx
    call fs_entry
    mov edi, eax
    cmp dword [edi+28], 0
    je .f
    inc ebx
    cmp ebx, FSMAX
    jb .l
    mov eax, -1
    jmp .x
.f:
    mov ecx, 23
.c:
    lodsb
    stosb
    test al, al
    jz .z
    dec ecx
    jnz .c
    mov byte [edi], 0
.z:
    mov eax, ebx
    call fs_entry
    mov dword [eax+24], 0
    mov dword [eax+28], 1
    mov eax, ebx
.x:
    pop edi
    pop esi
    pop ecx
    pop ebx
    ret

fs_delete:
    push eax
    call fs_entry
    mov dword [eax+28], 0
    call fs_savedir
    pop eax
    ret

; max 1k
fs_write:
    pushad
    cmp ecx, 1024
    jbe .ok
    mov ecx, 1024
.ok:
    mov ebx, eax
    call fs_entry
    mov [eax+24], ecx
    mov eax, ebx
    call fs_data
    mov edi, eax
    rep movsb
    call fs_savedir
    lea eax, [FSLBA+1+ebx*2]
    mov ecx, 2
    mov esi, ebx
    shl esi, 10
    add esi, FSMEM+512
    call ata_write
    popad
    ret
