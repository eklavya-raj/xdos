; FOP f, a, b, out
%macro FOP 4
    mov esi, %2
    mov ebx, %3
    mov edi, %4
    call %1
%endmacro

sha256:
    pushad
    mov [sh_out], edi
    mov [sh_len], ecx
    push esi
    mov esi, sha_h0
    mov edi, sh_h
    mov ecx, 8
    rep movsd
    pop esi
    mov ecx, [sh_len]
.blk:
    cmp ecx, 64
    jb .tail
    call sha_block
    add esi, 64
    sub ecx, 64
    jmp .blk
.tail:
    ; pad
    mov edi, sh_buf
    push ecx
    rep movsb
    pop ecx
    mov al, 0x80
    stosb
    push ecx
    lea ecx, [sh_buf+128]
    sub ecx, edi
    xor eax, eax
    rep stosb
    pop ecx
    mov esi, sh_buf
    cmp ecx, 56
    jb .one
    call sha_block
    add esi, 64
.one:
    mov eax, [sh_len]
    shl eax, 3
    bswap eax
    mov [esi+60], eax
    mov eax, [sh_len]
    shr eax, 29
    bswap eax
    mov [esi+56], eax
    call sha_block
    mov esi, sh_h
    mov edi, [sh_out]
    mov ecx, 8
.o:
    lodsd
    bswap eax
    stosd
    loop .o
    popad
    ret

sha_block:
    pushad
    mov edi, sh_w
    mov ecx, 16
.l:
    lodsd
    bswap eax
    stosd
    loop .l
    mov ecx, 48
.x:
    mov eax, [edi-8]
    mov ebx, eax
    mov edx, eax
    ror eax, 17
    ror ebx, 19
    shr edx, 10
    xor eax, ebx
    xor eax, edx
    add eax, [edi-28]
    add eax, [edi-64]
    mov ebx, [edi-60]
    mov edx, ebx
    mov ebp, ebx
    ror ebx, 7
    ror edx, 18
    shr ebp, 3
    xor ebx, edx
    xor ebx, ebp
    add eax, ebx
    stosd
    loop .x
    mov esi, sh_h
    mov edi, sh_v
    mov ecx, 8
    rep movsd
    xor ecx, ecx
.r:
    mov eax, [sh_v+16]
    mov ebx, eax
    mov edx, eax
    ror eax, 6
    ror ebx, 11
    ror edx, 25
    xor eax, ebx
    xor eax, edx
    mov ebx, [sh_v+16]
    mov edx, ebx
    and ebx, [sh_v+20]
    not edx
    and edx, [sh_v+24]
    xor ebx, edx
    add eax, ebx
    add eax, [sh_v+28]
    add eax, [sha_k+ecx*4]
    add eax, [sh_w+ecx*4]
    mov ebx, [sh_v]
    mov edx, ebx
    mov ebp, ebx
    ror ebx, 2
    ror edx, 13
    ror ebp, 22
    xor ebx, edx
    xor ebx, ebp
    mov edx, [sh_v]
    mov ebp, edx
    and edx, [sh_v+4]
    or ebp, [sh_v+4]
    and ebp, [sh_v+8]
    or edx, ebp
    add ebx, edx
    mov edx, 6
.s:
    mov ebp, [sh_v+edx*4]
    mov [sh_v+4+edx*4], ebp
    dec edx
    jns .s
    add [sh_v+16], eax
    add eax, ebx
    mov [sh_v], eax
    inc ecx
    cmp ecx, 64
    jb .r
    xor ecx, ecx
.a:
    mov eax, [sh_v+ecx*4]
    add [sh_h+ecx*4], eax
    inc ecx
    cmp ecx, 8
    jb .a
    popad
    ret

; key is 32 bytes
hmac:
    pushad
    push edi
    push ecx
    push ebx
    mov edi, HBUF
    mov dl, 0x36
    call hpad
    pop ebx
    pop ecx
    push esi
    mov esi, ebx
    push ecx
    rep movsb
    pop ecx
    pop esi
    push esi
    mov esi, HBUF
    add ecx, 64
    mov edi, HBUF2+64
    call sha256
    pop esi
    mov edi, HBUF2
    mov dl, 0x5C
    call hpad
    mov esi, HBUF2
    mov ecx, 96
    pop edi
    call sha256
    popad
    ret

hpad:
    push esi
    mov ecx, 64
.l:
    xor eax, eax
    cmp ecx, 32
    jbe .z
    lodsb
.z:
    xor al, dl
    stosb
    loop .l
    pop esi
    ret

;esi secret, ebx label, edx ctx or 0
hkdf_label:
    pushad
    mov [hk_out], edi
    mov [hk_len], ecx
    mov edi, LBUF
    mov al, 0
    stosb
    mov al, cl
    stosb
    movzx ecx, byte [ebx]
    lea eax, [ecx+6]
    stosb
    push esi
    mov esi, s_tls13
    movsd
    movsw
    lea esi, [ebx+1]
    rep movsb
    xor eax, eax
    test edx, edx
    jz .nc
    mov al, 32
    stosb
    mov esi, edx
    mov ecx, 32
    rep movsb
    jmp .c
.nc:
    stosb
.c:
    mov al, 1
    stosb
    pop esi
    mov ecx, edi
    sub ecx, LBUF
    mov ebx, LBUF
    mov edi, hk_tmp
    call hmac
    mov esi, hk_tmp
    mov edi, [hk_out]
    mov ecx, [hk_len]
    rep movsb
    popad
    ret

mp_add:
    pushad
    clc
.l:
    lodsd
    adc [edi], eax
    lea edi, [edi+4]
    loop .l
    popad
    ret

mp_mul:
    pushad
    mov [mm_m], edx
    push edi
    push ecx
    lea ecx, [ecx+edx]
    xor eax, eax
    rep stosd
    pop ecx
    pop edi
.i:
    push ecx
    push edi
    push ebx
    mov ecx, [mm_m]
    xor ebp, ebp
.j:
    mov eax, [ebx]
    mul dword [esi]
    add eax, ebp
    adc edx, 0
    add [edi], eax
    adc edx, 0
    mov ebp, edx
    add ebx, 4
    add edi, 4
    loop .j
    mov [edi], ebp
    pop ebx
    pop edi
    pop ecx
    add esi, 4
    add edi, 4
    loop .i
    popad
    ret

qr:
    push esi
    mov esi, [ebx]
    add [eax], esi
    mov esi, [eax]
    xor esi, [edx]
    rol esi, 16
    mov [edx], esi
    mov esi, [edx]
    add [ecx], esi
    mov esi, [ecx]
    xor esi, [ebx]
    rol esi, 12
    mov [ebx], esi
    mov esi, [ebx]
    add [eax], esi
    mov esi, [eax]
    xor esi, [edx]
    rol esi, 8
    mov [edx], esi
    mov esi, [edx]
    add [ecx], esi
    mov esi, [ecx]
    xor esi, [ebx]
    rol esi, 7
    mov [ebx], esi
    pop esi
    ret

chacha_block:
    pushad
    mov esi, cc_state
    mov edi, cc_out
    mov ecx, 16
    rep movsd
    mov dword [cc_rounds], 10
.r:
    mov esi, cc_qr
    mov ebp, 8
.q:
    movzx eax, byte [esi]
    movzx ebx, byte [esi+1]
    movzx ecx, byte [esi+2]
    movzx edx, byte [esi+3]
    lea eax, [cc_out+eax*4]
    lea ebx, [cc_out+ebx*4]
    lea ecx, [cc_out+ecx*4]
    lea edx, [cc_out+edx*4]
    call qr
    add esi, 4
    dec ebp
    jnz .q
    dec dword [cc_rounds]
    jnz .r
    xor ecx, ecx
.a:
    mov eax, [cc_state+ecx*4]
    add [cc_out+ecx*4], eax
    inc ecx
    cmp ecx, 16
    jb .a
    popad
    ret

chacha_xor:
    pushad
.b:
    test ecx, ecx
    jz .x
    call chacha_block
    inc dword [cc_state+48]
    mov ebx, cc_out
    mov edx, 64
.l:
    lodsb
    xor al, [ebx]
    stosb
    inc ebx
    dec ecx
    jz .x
    dec edx
    jnz .l
    jmp .b
.x:
    popad
    ret

; h = (h+m)*r mod 2^130-5
poly_block:
    pushad
    mov edi, p_h
    lodsd
    add [edi], eax
    lodsd
    adc [edi+4], eax
    lodsd
    adc [edi+8], eax
    lodsd
    adc [edi+12], eax
    adc dword [edi+16], 1
    and dword [p_p+36], 0
    mov esi, p_h
    mov ebx, p_r
    mov edi, p_p
    mov ecx, 5
    mov edx, 4
    call mp_mul
    xor ecx, ecx
.s:
    mov eax, [p_p+16+ecx*4]
    mov edx, [p_p+20+ecx*4]
    shrd eax, edx, 2
    mov [p_t+ecx*4], eax
    inc ecx
    cmp ecx, 5
    jb .s
    mov esi, p_p
    mov edi, p_h
    movsd
    movsd
    movsd
    movsd
    mov eax, [esi]
    and eax, 3
    mov [edi], eax
    mov esi, p_t
    mov edi, p_h
    mov ecx, 5
    call mp_add
    mov ecx, 4
.l:
    mov eax, [p_t+ecx*4]
    mov edx, [p_t-4+ecx*4]
    shld eax, edx, 2
    mov [p_t+ecx*4], eax
    loop .l
    shl dword [p_t], 2
    mov esi, p_t
    mov edi, p_h
    mov ecx, 5
    call mp_add
    popad
    ret

poly_data:
    pushad
.l:
    cmp ecx, 0
    jle .x
    push ecx
    mov edi, p_blk
    xor eax, eax
    mov ecx, 4
    rep stosd
    pop ecx
    push ecx
    cmp ecx, 16
    jbe .c
    mov ecx, 16
.c:
    mov edi, p_blk
    rep movsb
    pop ecx
    push esi
    mov esi, p_blk
    call poly_block
    pop esi
    sub ecx, 16
    jmp .l
.x:
    popad
    ret

poly_finish:
    pushad
    mov ecx, 2
.f:
    mov eax, [p_h+16]
    mov edx, eax
    shr edx, 2
    and eax, 3
    mov [p_h+16], eax
    lea edx, [edx+edx*4]
    add [p_h], edx
    adc dword [p_h+4], 0
    adc dword [p_h+8], 0
    adc dword [p_h+12], 0
    adc dword [p_h+16], 0
    loop .f
    mov esi, p_h
    push edi
    mov edi, p_t
    mov ecx, 5
    rep movsd
    pop edi
    add dword [p_t], 5
    adc dword [p_t+4], 0
    adc dword [p_t+8], 0
    adc dword [p_t+12], 0
    adc dword [p_t+16], 0
    mov esi, p_h
    test dword [p_t+16], 4
    jz .u
    mov esi, p_t
.u:
    lodsd
    add eax, [p_s]
    stosd
    lodsd
    adc eax, [p_s+4]
    stosd
    lodsd
    adc eax, [p_s+8]
    stosd
    lodsd
    adc eax, [p_s+12]
    stosd
    popad
    ret

; al=1 encrypt. key/iv/seq at ebx
aead:
    pushad
    mov [ae_enc], al
    mov [ae_data], edi
    mov [ae_len], ecx
    mov [ae_aad], esi
    mov dword [cc_state], 0x61707865
    mov dword [cc_state+4], 0x3320646e
    mov dword [cc_state+8], 0x79622d32
    mov dword [cc_state+12], 0x6b206574
    mov esi, ebx
    mov edi, cc_state+16
    mov ecx, 8
    rep movsd
    xor eax, eax
    stosd
    movsd
    movsd
    movsd
    ;nonce=iv ^ seq
    mov eax, [ebx+44]
    bswap eax
    xor [cc_state+60], eax
    inc dword [ebx+44]
    ; block 0->poly key
    call chacha_block
    mov esi, cc_out
    mov edi, p_r
    mov ecx, 8
    rep movsd
    and dword [p_r], 0x0FFFFFFF
    and dword [p_r+4], 0x0FFFFFFC
    and dword [p_r+8], 0x0FFFFFFC
    and dword [p_r+12], 0x0FFFFFFC
    xor eax, eax
    mov edi, p_h
    mov ecx, 5
    rep stosd
    mov dword [cc_state+48], 1
    cmp byte [ae_enc], 0
    je .mac
    call .xor
.mac:
    mov esi, [ae_aad]
    mov ecx, 5
    call poly_data
    mov esi, [ae_data]
    mov ecx, [ae_len]
    call poly_data
    mov dword [p_len], 5
    and dword [p_len+4], 0
    mov eax, [ae_len]
    mov [p_len+8], eax
    and dword [p_len+12], 0
    mov esi, p_len
    call poly_block
    mov edi, p_tag
    call poly_finish
    cmp byte [ae_enc], 0
    jne .x
    call .xor
.x:
    popad
    ret
.xor:
    mov esi, [ae_data]
    mov edi, esi
    mov ecx, [ae_len]
    jmp chacha_xor

;  mod 2^255-19, 2^256 = 38
fe_fold:
    pushad
    mov ecx, 8
    push edi
    rep movsd
    pop edi
.f:
    add [edi], ebp
    mov ecx, 7
    lea esi, [edi+4]
.p:
    adc dword [esi], 0
    lea esi, [esi+4]
    loop .p
    mov ebp, 38
    jc .f
    popad
    ret

fe_add:
    pushad
    mov ecx, 8
    push edi
    rep movsd
    pop edi
    mov esi, ebx
    mov ecx, 8
    call mp_add
    sbb ebp, ebp
    and ebp, 38
    mov esi, edi
    call fe_fold
    popad
    ret

fe_sub:
    pushad
    mov ecx, 8
    push edi
    rep movsd
    pop edi
    mov esi, ebx
    mov ecx, 8
    push edi
    clc
.l:
    lodsd
    sbb [edi], eax
    lea edi, [edi+4]
    loop .l
    pop edi
.b:
    jnc .x
    sub dword [edi], 38
    mov ecx, 7
    lea esi, [edi+4]
.p:
    sbb dword [esi], 0
    lea esi, [esi+4]
    loop .p
    jmp .b
.x:
    popad
    ret

fe_mul:
    pushad
    push edi
    mov edi, fe_p
    mov ecx, 8
    mov edx, 8
    call mp_mul
    xor ebp, ebp
    xor ecx, ecx
.r:
    mov eax, [fe_p+32+ecx*4]
    mov edx, 38
    mul edx
    add eax, ebp
    adc edx, 0
    add eax, [fe_p+ecx*4]
    adc edx, 0
    mov [fe_p+ecx*4], eax
    mov ebp, edx
    inc ecx
    cmp ecx, 8
    jb .r
    imul ebp, ebp, 38
    pop edi
    mov esi, fe_p
    call fe_fold
    popad
    ret

fe_inv:
    pushad
    mov [fi_a], esi
    mov [fi_o], edi
    mov edi, fi_r
    mov ecx, 8
    rep movsd
    mov ecx, 253
.l:
    FOP fe_mul, fi_r, fi_r, fi_r
    cmp ecx, 4
    je .n
    cmp ecx, 2
    je .n
    mov esi, fi_r
    mov ebx, [fi_a]
    mov edi, fi_r
    call fe_mul
.n:
    dec ecx
    jns .l
    mov esi, fi_r
    mov edi, [fi_o]
    mov ecx, 8
    rep movsd
    popad
    ret

fe_final:
    pushad
    mov ecx, 2
.f:
    mov eax, [edi+28]
    shr eax, 31
    and dword [edi+28], 0x7FFFFFFF
    imul ebp, eax, 19
    mov esi, edi
    call fe_fold
    loop .f
    mov esi, edi
    push edi
    mov edi, fe_t
    mov ebp, 19
    call fe_fold
    pop edi
    test byte [fe_t+31], 0x80
    jz .x
    and byte [fe_t+31], 0x7F
    mov esi, fe_t
    mov ecx, 8
    rep movsd
.x:
    popad
    ret

; not constant time
cswap:
    test eax, eax
    jz .x
    pushad
    xor ecx, ecx
.l:
    mov eax, [x2+ecx*4]
    xchg eax, [x3+ecx*4]
    mov [x2+ecx*4], eax
    mov eax, [z2+ecx*4]
    xchg eax, [z3+ecx*4]
    mov [z2+ecx*4], eax
    inc ecx
    cmp ecx, 8
    jb .l
    popad
.x:
    ret

;montgomery ladder
x25519:
    pushad
    mov [xk_out], edi
    mov edi, xk
    mov ecx, 8
    rep movsd
    and byte [xk], 248
    and byte [xk+31], 127
    or byte [xk+31], 64
    mov esi, ebx
    mov edi, x1
    mov ecx, 8
    rep movsd
    and byte [x1+31], 127
    xor eax, eax
    mov edi, x2
    mov ecx, 16
    rep stosd
    mov byte [x2], 1
    mov esi, x1
    mov edi, x3
    mov ecx, 8
    rep movsd
    mov ecx, 8
    rep stosd
    mov byte [z3], 1
    and dword [xs_swap], 0
    mov ecx, 254
.l:
    xor eax, eax
    bt [xk], ecx
    adc eax, 0
    push eax
    xor eax, [xs_swap]
    call cswap
    pop eax
    mov [xs_swap], eax
    FOP fe_add, x2, z2, xA
    FOP fe_mul, xA, xA, xAA
    FOP fe_sub, x2, z2, xB
    FOP fe_mul, xB, xB, xBB
    FOP fe_sub, xAA, xBB, xE
    FOP fe_add, x3, z3, xC
    FOP fe_sub, x3, z3, xD
    FOP fe_mul, xD, xA, xDA
    FOP fe_mul, xC, xB, xCB
    FOP fe_add, xDA, xCB, xT
    FOP fe_mul, xT, xT, x3
    FOP fe_sub, xDA, xCB, xT
    FOP fe_mul, xT, xT, xT
    FOP fe_mul, x1, xT, z3
    FOP fe_mul, xAA, xBB, x2
    FOP fe_mul, a24, xE, xT
    FOP fe_add, xAA, xT, xT2
    FOP fe_mul, xE, xT2, z2
    dec ecx
    jns .l
    mov eax, [xs_swap]
    call cswap
    mov esi, z2
    mov edi, xT
    call fe_inv
    FOP fe_mul, x2, xT, xT2
    mov edi, xT2
    call fe_final
    mov esi, xT2
    mov edi, [xk_out]
    mov ecx, 8
    rep movsd
    popad
    ret

;build with -dCRYPTOTEST
%ifdef CRYPTOTEST
TIN  equ 0x3100000
TOUT equ 0x3000000
crypto_test:
    mov edi, TIN
    xor ecx, ecx
.f:
    lea eax, [ecx*8]
    sub eax, ecx
    inc eax
    stosb
    inc ecx
    cmp ecx, 512
    jb .f
    mov edi, TOUT
    mov ebx, t_lens
.s:
    movzx ecx, word [ebx]
    cmp ecx, 0xFFFF
    je .h
    mov esi, TIN
    call sha256
    add edi, 32
    add ebx, 2
    jmp .s
.h:
    mov esi, TIN
    mov ebx, TIN+32
    mov ecx, 50
    call hmac
    add edi, 32
    mov esi, TIN
    mov ebx, l_chs
    mov edx, TIN+64
    mov ecx, 32
    call hkdf_label
    add edi, 32
    mov esi, TIN
    mov ebx, l_iv
    xor edx, edx
    mov ecx, 12
    call hkdf_label
    add edi, 12
    mov esi, TIN
    mov ebx, TIN+32
    call x25519
    add edi, 32
    mov esi, TIN
    mov ebx, x_base
    call x25519
    add edi, 32
    push edi
    mov esi, TIN+200
    mov ecx, 100
    rep movsb
    pop edi
    mov esi, TIN+100
    push edi
    mov edi, TIN+600
    mov ecx, 44
    rep movsb
    mov dword [edi], 5
    pop edi
    mov ebx, TIN+600
    mov esi, TIN+400
    mov ecx, 100
    mov al, 1
    call aead
    add edi, 100
    mov esi, p_tag
    movsd
    movsd
    movsd
    movsd
    mov dword [edi], 0x21444F4E
    ret
t_lens dw 0, 3, 55, 56, 63, 64, 100, 200, 0xFFFF
%endif
