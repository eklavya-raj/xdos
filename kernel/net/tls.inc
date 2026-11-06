; tls 1.3,chacha20-poly1305 + x25519 only. no cert checks
RAWBUF  equ 0x2C00000

tcp_write:
    pushad
    mov bl, 0x18
    call tcp_send
    add [sndnxt], ecx
    popad
    ret

strlen:
    push esi
    xor ecx, ecx
.l:
    lodsb
    test al, al
    jz .x
    inc ecx
    jmp .l
.x:
    pop esi
    ret

tr_add:
    pushad
    mov edi, [trlen]
    add [trlen], ecx
    add edi, TRANS
    rep movsb
    popad
    ret

tr_hash:
    pushad
    mov esi, TRANS
    mov ecx, [trlen]
    mov edi, tl_th
    call sha256
    popad
    ret

derive:
    mov edx, tl_th
    mov ecx, 32
    jmp hkdf_label

set_keys:
    pushad
    mov ebx, l_key
    xor edx, edx
    mov ecx, 32
    call hkdf_label
    add edi, 32
    mov ebx, l_iv
    mov ecx, 12
    call hkdf_label
    and dword [edi+12], 0
    popad
    ret

;rdtsc + ticks + mouse
tls_rand:
    mov edi, LBUF
    mov ecx, 32
.l:
    rdtsc
    xor eax, [ticks]
    add eax, [mx]
    stosd
    loop .l
    mov esi, LBUF
    mov ecx, 128
    mov edi, tl_priv
    call sha256
    rdtsc
    xor [LBUF], eax
    mov edi, tl_rand
    jmp sha256

build_ch:
    mov edi, TLSOUT+5
    mov eax, 1
    stosd
    mov ax, 0x0303
    stosw
    mov esi, tl_rand
    mov ecx, 8
    rep movsd
    mov al, 0
    stosb
    mov eax, 0x03130200
    stosd
    mov ax, 0x0001
    stosw
    push edi
    add edi, 2
    mov esi, b_host
    call strlen
    xor eax, eax
    stosw
    lea eax, [ecx+5]
    xchg al, ah
    stosw
    lea eax, [ecx+3]
    xchg al, ah
    stosw
    mov al, 0
    stosb
    mov eax, ecx
    xchg al, ah
    stosw
    rep movsb
    mov esi, ch_ext
    mov ecx, ch_ext_end-ch_ext
    rep movsb
    mov esi, tl_pub
    mov ecx, 8
    rep movsd
    pop ebx
    mov eax, edi
    sub eax, ebx
    sub eax, 2
    xchg al, ah
    mov [ebx], ax
    mov eax, edi
    sub eax, TLSOUT+9
    bswap eax
    or al, 1
    mov [TLSOUT+5], eax
    mov dword [TLSOUT], 0x00010316
    mov eax, edi
    sub eax, TLSOUT+5
    xchg al, ah
    mov [TLSOUT+3], ax
    mov esi, TLSOUT+5
    mov ecx, edi
    sub ecx, esi
    and dword [trlen], 0
    call tr_add
    mov ecx, edi
    sub ecx, TLSOUT
    ret

tls_need:
    push eax
    mov eax, [ticks]
    mov [tn_t], eax
.l:
    mov eax, [pagelen]
    sub eax, [rpos]
    cmp eax, ecx
    jae .ok
    cmp dword [tstate], 3
    je .no
    mov eax, [ticks]
    sub eax, [tn_t]
    cmp eax, 1300
    ja .no
    push ecx
    call co_switch
    call net_poll
    pop ecx
    jmp .l
.ok:
    pop eax
    clc
    ret
.no:
    pop eax
    stc
    ret

;  al type,esi body,ecx len
tls_rec:
    mov ecx, 5
    call tls_need
    jc .x
    mov esi, RAWBUF
    add esi, [rpos]
    movzx ecx, word [esi+3]
    xchg cl, ch
    push ecx
    add ecx, 5
    call tls_need
    pop ecx
    jc .x
    mov esi, RAWBUF
    add esi, [rpos]
    mov al, [esi]
    add esi, 5
    lea edx, [ecx+5]
    add [rpos], edx
    clc
.x:
    ret

tls_open:
    sub ecx, 16
    jb .bad
    push esi
    push ecx
    mov edi, esi
    lea esi, [edi-5]
    mov ebx, rx_k
    xor al, al
    call aead
    mov esi, [esp+4]
    mov ecx, [esp]
    lea edi, [esi+ecx]
    mov esi, p_tag
    mov ecx, 16
    repe cmpsb ;tag ok?
    pop ecx
    pop esi
    jne .bad
.z:
    dec ecx
    js .bad
    mov al, [esi+ecx]
    test al, al
    jz .z
    clc
    ret
.bad:
    stc
    ret

tls_send:
    pushad
    mov edi, TLSOUT+5
    rep movsb
    stosb
    mov ecx, [esp+24]
    inc ecx
    lea eax, [ecx+16]
    xchg al, ah
    mov dword [TLSOUT], 0x00030317
    mov [TLSOUT+3], ax
    mov esi, TLSOUT
    mov edi, TLSOUT+5
    mov ebx, tx_k
    mov al, 1
    call aead
    add edi, ecx
    mov esi, p_tag
    movsd
    movsd
    movsd
    movsd
    add ecx, 21
    mov esi, TLSOUT
    call tcp_write
    popad
    ret

tls_run:
    and dword [rpos], 0
    and dword [tl_outlen], 0
    call tls_rand
    mov esi, tl_priv
    mov ebx, x_base
    mov edi, tl_pub
    call x25519
    call build_ch
    mov esi, TLSOUT
    call tcp_write
.sh:
    ; server hello
    call tls_rec
    jc .fail
    cmp al, 20
    je .sh
    cmp al, 22
    jne .fail
    cmp byte [esi], 2
    jne .fail
    call tr_add
    lea edx, [esi+38]
    movzx eax, byte [edx]
    lea edx, [edx+eax+1]
    cmp word [edx], 0x0313
    jne .fail
    add edx, 3
    movzx ecx, word [edx]
    xchg cl, ch
    add edx, 2
    lea ebx, [edx+ecx]
.e:
    cmp edx, ebx
    jae .fail
    movzx ecx, word [edx+2]
    xchg cl, ch
    cmp word [edx], 0x3300
    je .ks
    lea edx, [edx+ecx+4]
    jmp .e
.ks:
    ; key share
    cmp word [edx+6], 0x2000
    jne .fail
    lea ebx, [edx+8]
    mov esi, tl_priv
    mov edi, tl_shared
    call x25519
    mov esi, tl_zero
    mov ebx, tl_zero
    mov ecx, 32
    mov edi, tl_sec
    call hmac
    xor ecx, ecx
    mov edi, tl_eh
    call sha256
    mov esi, tl_sec
    mov ebx, l_derived
    mov edx, tl_eh
    mov ecx, 32
    mov edi, tl_tmp
    call hkdf_label
    mov esi, tl_tmp
    mov ebx, tl_shared
    mov ecx, 32
    mov edi, tl_sec
    call hmac
    call tr_hash
    mov esi, tl_sec
    mov ebx, l_chs
    mov edi, tl_chs
    call derive
    mov ebx, l_shs
    mov edi, tl_shs
    call derive
    mov ebx, l_derived
    mov edx, tl_eh
    mov ecx, 32
    mov edi, tl_tmp
    call hkdf_label
    mov esi, tl_tmp
    mov ebx, tl_zero
    mov ecx, 32
    mov edi, tl_sec
    call hmac
    mov esi, tl_shs
    mov edi, rx_k
    call set_keys
    mov eax, [trlen]
    mov [tl_hs0], eax
.hs:
    call tls_rec
    jc .fail
    cmp al, 20
    je .hs
    cmp al, 23
    jne .fail
    ; no cert check, just wait for finished
    call tls_open
    jc .fail
    cmp al, 22
    jne .fail
    call tr_add
    mov edx, [tl_hs0]
.sc:
    lea eax, [edx+4]
    cmp eax, [trlen]
    ja .hs
    mov eax, [TRANS+edx]
    bswap eax
    and eax, 0xFFFFFF
    lea ecx, [edx+eax+4]
    cmp ecx, [trlen]
    ja .hs
    cmp byte [TRANS+edx], 20
    je .fin
    mov edx, ecx
    jmp .sc
.fin:
    mov [trlen], ecx
    call tr_hash
    mov esi, tl_sec
    mov ebx, l_cap
    mov edi, tl_cap
    call derive
    mov ebx, l_sap
    mov edi, tl_sap
    call derive
    mov esi, tl_chs
    mov ebx, l_fin
    xor edx, edx
    mov ecx, 32
    mov edi, tl_tmp
    call hkdf_label
    mov esi, tl_tmp
    mov ebx, tl_th
    mov ecx, 32
    mov edi, tl_fmsg+4
    call hmac
    mov dword [tl_fmsg], 0x20000014
    mov esi, tl_chs
    mov edi, tx_k
    call set_keys
    mov esi, tl_fmsg
    mov ecx, 36
    mov al, 22
    call tls_send
    mov esi, tl_cap
    mov edi, tx_k
    call set_keys
    mov esi, tl_sap
    mov edi, rx_k
    call set_keys
    mov esi, reqbuf
    mov ecx, [reqlen]
    mov al, 23
    call tls_send
.ap:
    call tls_rec
    jc .done
    cmp al, 23
    jne .done
    call tls_open
    jc .done
    cmp al, 23
    jne .ap
    mov edi, [tl_out]
    add edi, [tl_outlen]
    mov eax, [tl_outlen]
    add eax, ecx
    cmp eax, PAGEMAX
    ja .ap
    mov [tl_outlen], eax
    rep movsb
    jmp .ap
.done:
    xor eax, eax
    ret
.fail:
    mov eax, e_tlsf
    ret

tls_on   dd 0
dport    dw 0x5000
tl_out   dd 0
tl_outlen dd 0
tl_hs0   dd 0
rpos     dd 0
trlen    dd 0
tn_t     dd 0
s_tls13  db 'tls13 '
l_derived db 7, 'derived'
l_chs    db 12, 'c hs traffic'
l_shs    db 12, 's hs traffic'
l_cap    db 12, 'c ap traffic'
l_sap    db 12, 's ap traffic'
l_key    db 3, 'key'
l_iv     db 2, 'iv'
l_fin    db 8, 'finished'
e_tlsf   db 'TLS failed', 0
cc_qr    db 0, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15, 0, 5, 10, 15, 1, 6, 11, 12, 2, 7, 8, 13, 3, 4, 9, 14
x_base   db 9
tl_zero  times 32 db 0
a24      dd 121665, 0, 0, 0, 0, 0, 0, 0
ch_ext:
    db 0x00, 0x0a, 0x00, 0x04, 0x00, 0x02, 0x00, 0x1d
    db 0x00, 0x0d, 0x00, 0x14, 0x00, 0x12
    db 0x04, 0x03, 0x08, 0x04, 0x04, 0x01, 0x05, 0x03, 0x08, 0x05, 0x05, 0x01, 0x08, 0x06, 0x06, 0x01, 0x08, 0x07
    db 0x00, 0x2b, 0x00, 0x03, 0x02, 0x03, 0x04
    db 0x00, 0x33, 0x00, 0x26, 0x00, 0x24, 0x00, 0x1d, 0x00, 0x20
ch_ext_end:
