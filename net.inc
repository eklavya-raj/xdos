RXBUF   equ 0x2200000
TXBUF   equ 0x2280000
PAGE    equ 0x2300000
PAGEMAX equ 0xF0000

;find the 8139 on pci
net_init:
    cmp dword [nic], 0
    jne .ok
    xor ebx, ebx
.s:
    mov eax, ebx
    shl eax, 11
    or eax, 0x80000000
    mov [pcia], eax
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx
    cmp eax, 0x813910EC	; 10ec:8139
    je .found
    inc ebx
    cmp ebx, 32
    jb .s
    xor eax, eax
    ret
.found:
    mov eax, [pcia]
    ; bar0
    or eax, 0x10
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx
    and eax, 0xFFFC
    mov [nic], eax
    mov eax, [pcia]
    ; io + bus master
    or eax, 4
    mov dx, 0xCF8
    out dx, eax
    mov dx, 0xCFC
    in eax, dx
    or eax, 5
    out dx, eax
    mov edx, [nic]
    ; power on + reset
    add edx, 0x52
    xor al, al
    out dx, al
    mov edx, [nic]
    add edx, 0x37
    mov al, 0x10
    out dx, al
.r:
    in al, dx
    test al, 0x10
    jnz .r
    mov edx, [nic]
    add edx, 0x30
    mov eax, RXBUF
    out dx, eax
    mov edx, [nic]
    add edx, 0x3C
    xor ax, ax
    out dx, ax
    mov edx, [nic]
    add edx, 0x44
    mov eax, 0x188F
    out dx, eax
    mov edx, [nic]
    add edx, 0x37
    mov al, 0x0C
    out dx, al
    ; mac
    xor ecx, ecx
.m:
    mov edx, [nic]
    add edx, ecx
    in al, dx
    mov [mac+ecx], al
    inc ecx
    cmp ecx, 6
    jb .m
.ok:
    mov eax, 1
    ret

nic_send:
    pushad
    cmp ecx, 60
    jae .l
    mov ecx, 60
.l:
    mov ebx, [txi]
    mov edx, [nic]
    lea edx, [edx+ebx*4+0x20]
    mov eax, TXBUF
    out dx, eax
    mov edx, [nic]
    lea edx, [edx+ebx*4+0x10]
    mov eax, ecx
    out dx, eax
    mov ecx, 2000000
.w:
    in eax, dx
    test eax, 0x8000
    jnz .d
    dec ecx
    jnz .w
.d:
    inc ebx
    and ebx, 3	; 4 tx slots
    mov [txi], ebx
    popad
    ret

; cf = nothing
nic_recv:
    mov edx, [nic]
    add edx, 0x37
    in al, dx
    test al, 1
    jnz .none
    mov eax, [rxoff]
    lea esi, [RXBUF+eax]
    movzx ecx, word [esi+2]
    add esi, 4
    lea eax, [eax+ecx+4+3]
    and eax, 0xFFFC
    mov [rxoff], eax
    sub eax, 16		; capr - 16, 8139 thing
    mov edx, [nic]
    add edx, 0x38
    out dx, ax
    sub ecx, 4
    clc
    ret
.none:
    stc
    ret

csum:
    push ebx
    push edx
    mov ebx, ecx
    xor eax, eax
    shr ecx, 1
    jz .t
.l:
    movzx edx, word [esi]
    add eax, edx
    add esi, 2
    dec ecx
    jnz .l
.t:
    test bl, 1
    jz .f
    movzx edx, byte [esi]
    add eax, edx
.f:
    mov edx, eax
    shr edx, 16
    jz .n
    and eax, 0xFFFF
    add eax, edx
    jmp .f
.n:
    not ax
    pop edx
    pop ebx
    ret

eth_start:
    mov edi, TXBUF
    mov esi, gwmac
    movsd
    movsw
    mov esi, mac
    movsd
    movsw
    mov word [edi], 0x0008
    ret

arp_head:
    mov esi, mac
    movsd
    movsw
    mov eax, 0x01000608
    stosd
    mov eax, 0x04060008
    stosd
    mov eax, ebx
    stosw
    mov esi, mac
    movsd
    movsw
    mov eax, [ourip]
    stosd
    ret

arp_send:
    pushad
    mov edi, TXBUF
    or eax, -1
    stosd
    stosw
    mov ebx, 0x0100
    call arp_head
    xor eax, eax
    stosd
    stosw
    mov eax, [gwip]
    stosd
    mov ecx, 42
    call nic_send
    popad
    ret

ip_hdr:
    pushad
    mov edi, TXBUF+14
    mov byte [edi], 0x45
    mov byte [edi+1], 0
    lea eax, [ecx+20]
    xchg al, ah
    mov [edi+2], ax
    inc word [ipid]
    mov ax, [ipid]
    mov [edi+4], ax
    mov word [edi+6], 0x0040
    mov byte [edi+8], 64
    mov [edi+9], bl
    mov word [edi+10], 0
    mov eax, [ourip]
    mov [edi+12], eax
    mov eax, [dstip]
    mov [edi+16], eax
    mov esi, edi
    mov ecx, 20
    call csum
    mov [edi+10], ax
    popad
    ret

tcp_send:
    pushad
    mov [tplen], ecx
    mov edi, TXBUF+54
    rep movsb
    mov edi, TXBUF+34
    mov ax, [sport]
    mov [edi], ax
    mov word [edi+2], 0x5000
    mov eax, [sndnxt]
    bswap eax                       ; net order
    mov [edi+4], eax
    mov eax, [rcvnxt]
    bswap eax
    mov [edi+8], eax
    mov byte [edi+12], 0x50
    mov [edi+13], bl
    mov word [edi+14], 0x0040
    and dword [edi+16], 0
    ;pseudo header, ip_hdr overwrites it after
    mov esi, TXBUF+22
    mov eax, [ourip]
    mov [esi], eax
    mov eax, [dstip]
    mov [esi+4], eax
    mov word [esi+8], 0x0600
    mov eax, [tplen]
    add eax, 20
    xchg al, ah
    mov [esi+10], ax
    mov ecx, [tplen]
    add ecx, 32
    call csum
    mov [TXBUF+50], ax
    mov bl, 6
    mov ecx, [tplen]
    add ecx, 20
    call ip_hdr
    call eth_start
    mov ecx, [tplen]
    add ecx, 54
    call nic_send
    popad
    ret

net_poll:
    call nic_recv
    jc .x
    mov ax, [esi+12]
    cmp ax, 0x0608
    je .arp
    cmp ax, 0x0008
    jne .x
    mov al, [esi+23]
    cmp al, 17
    je dns_in
    cmp al, 6
    je tcp_in
.x:
    ret
.arp:
    cmp word [esi+20], 0x0200
    jne .req
    mov eax, [esi+28]
    cmp eax, [gwip]
    jne .x
    mov eax, [esi+22]
    mov [gwmac], eax
    mov ax, [esi+26]
    mov [gwmac+4], ax
    mov dword [haveg], 1
    ret
.req:
    mov eax, [esi+38]
    cmp eax, [ourip]
    jne .x
    mov edi, TXBUF
    push esi
    add esi, 6
    movsd
    movsw
    mov ebx, 0x0200
    call arp_head
    pop esi
    add esi, 22
    movsd
    movsw
    movsd
    mov ecx, 42
    jmp nic_send

dns_in:
    cmp word [esi+36], 0x409C
    jne .x
    cmp word [esi+42], 0x3412
    jne .x
    movzx ecx, word [esi+48]
    xchg cl, ch
    lea edi, [esi+54]
.q:
    mov al, [edi]
    test al, al
    jz .qe
    movzx eax, al
    lea edi, [edi+eax+1]
    jmp .q
.qe:
    add edi, 5
.a:
    test ecx, ecx
    jz .x
    mov al, [edi]
    test al, 0xC0
    jz .long
    add edi, 2
    jmp .r
.long:
    test al, al
    jz .end
    movzx eax, al
    lea edi, [edi+eax+1]
    jmp .long2
.long2:
    mov al, [edi]
    jmp .long
.end:
    inc edi
.r:
    movzx ebx, word [edi+8]
    xchg bl, bh
    cmp word [edi], 0x0100
    je .hit
    lea edi, [edi+ebx+10]
    dec ecx
    jmp .a
.hit:
    mov eax, [edi+10]
    mov [dstip], eax
    mov dword [haveip], 1
.x:
    ret

; tstate 1 syn sent,2 open,3 closed
tcp_in:
    mov ax, [esi+36]
    cmp ax, [sport]
    jne .x
    movzx edx, word [esi+16]
    xchg dl, dh
    movzx ebx, byte [esi+46]
    shr ebx, 4
    shl ebx, 2
    sub edx, 20
    sub edx, ebx
    mov al, [esi+47]
    mov [tflags], al
    test al, 4
    jnz .closed
    mov eax, [esi+38]
    bswap eax
    cmp dword [tstate], 1
    jne .est
    test byte [tflags], 0x12
    jz .x
    inc eax
    mov [rcvnxt], eax
    inc dword [sndnxt]
    mov dword [tstate], 2
    mov bl, 0x10
    xor ecx, ecx
    call tcp_send
    mov bl, 0x18
    mov esi, reqbuf
    mov ecx, [reqlen]
    call tcp_send
    add [sndnxt], ecx
    ret
.est:
    cmp dword [tstate], 2
    jne .x
    cmp eax, [rcvnxt]
    jne .re
    test edx, edx
    jz .fin
    lea esi, [esi+34+ebx]
    mov edi, PAGE
    add edi, [pagelen]
    mov ecx, edx
    mov eax, [pagelen]
    add eax, ecx
    cmp eax, PAGEMAX
    ja .skip
    mov [pagelen], eax
    rep movsb
.skip:
    add [rcvnxt], edx
.fin:
    test byte [tflags], 1
    jz .ack
    inc dword [rcvnxt]
    mov bl, 0x11
    xor ecx, ecx
    call tcp_send
.closed:
    mov dword [tstate], 3
    ret
.ack:
.re:
    mov bl, 0x10
    xor ecx, ecx
    call tcp_send
.x:
    ret

wait_for:
    mov eax, [ticks]
    mov [wcount], eax
.l:
    call net_poll
    mov eax, [esi_flag]
    mov eax, [eax]
    test eax, eax
    jz .t
    mov ecx, [ebx_flag]
    cmp ecx, -1
    je .ok
    cmp eax, ecx
    jae .ok
.t:
    mov eax, [ticks]
    sub eax, [wcount]
    cmp eax, 1300
    jb .l
    xor eax, eax
    ret
.ok:
    mov eax, 1
    ret

net_get:
    call net_init
    test eax, eax
    jnz .nic
    mov eax, e_nonic
    ret
.nic:
    cmp dword [haveg], 0
    jne .gw
    call arp_send
    mov dword [esi_flag], haveg
    or dword [ebx_flag], -1
    call wait_for
    test eax, eax
    jnz .gw
    mov eax, e_arp
    ret
.gw:
    and dword [haveip], 0
    mov edi, TXBUF+42
    ; dns query
    mov word [edi], 0x3412
    mov word [edi+2], 0x0001
    mov dword [edi+4], 0x00000100
    and dword [edi+8], 0
    add edi, 12
    mov esi, b_host
.lab:
    mov ebx, edi
    inc edi
    xor ecx, ecx
.ch:
    lodsb
    cmp al, '.'
    je .ld
    test al, al
    jz .ld
    stosb
    inc ecx
    jmp .ch
.ld:
    mov [ebx], cl
    test al, al
    jnz .lab
    xor al, al
    stosb
    mov dword [edi], 0x01000100
    add edi, 4
    mov ecx, edi
    sub ecx, TXBUF+34
    mov edi, TXBUF+34
    mov word [edi], 0x409C
    mov word [edi+2], 0x3500
    mov eax, ecx
    xchg al, ah
    mov [edi+4], ax
    mov word [edi+6], 0
    mov eax, [dnsip]
    mov [dstip], eax
    mov bl, 17
    call ip_hdr
    add ecx, 34
    push ecx
    call eth_start
    pop ecx
    call nic_send
    mov dword [esi_flag], haveip
    or dword [ebx_flag], -1
    call wait_for
    test eax, eax
    jnz .dns
    mov eax, e_dns
    ret
.dns:
    call build_req
    inc word [sportn]
    mov ax, [sportn]
    xchg al, ah
    mov [sport], ax
    add dword [sndnxt], 0x10000
    and dword [pagelen], 0
    mov dword [tstate], 1
    mov bl, 2
    xor ecx, ecx
    call tcp_send
    mov dword [esi_flag], tstate
    mov dword [ebx_flag], 3
    call wait_for
    test eax, eax
    jnz .done
    cmp dword [pagelen], 0
    jne .done
    mov eax, e_tcp
    ret
.done:
    xor eax, eax
    ret

build_req:
    mov edi, reqbuf
    mov esi, r_get
    call scopy
    mov esi, b_path
    call scopy
    mov esi, r_host
    call scopy
    mov esi, b_host
    call scopy
    mov esi, r_end
    call scopy
    sub edi, reqbuf
    mov [reqlen], edi
    ret

scopy:
    lodsb
    test al, al
    jz .x
    stosb
    jmp scopy
.x:
    ret

nic      dd 0
pcia     dd 0
txi      dd 0
rxoff    dd 0
haveg    dd 0
haveip   dd 0
tstate   dd 0
tflags   dd 0
tplen    dd 0
reqlen   dd 0
pagelen  dd 0
sndnxt   dd 0x1000
rcvnxt   dd 0
wcount   dd 0
esi_flag dd 0
ebx_flag dd 0
sport    dw 0
sportn   dw 49152
ipid     dw 1
mac      times 6 db 0
gwmac    times 6 db 0
ourip    db 10, 0, 2, 15
gwip     db 10, 0, 2, 2
dnsip    db 10, 0, 2, 3
dstip    dd 0
r_get    db 'GET ', 0
r_host   db ' HTTP/1.0', 13, 10, 'Host: ', 0
r_end    db 13, 10, 13, 10, 0
e_nonic  db 'No network', 0
e_arp    equ e_nonic
e_dns    db 'Site not found', 0
e_tcp    equ e_dns
reqbuf   times 320 db 0
