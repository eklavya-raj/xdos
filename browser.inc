WORDS   equ 0x2400000 ; x y text w link head
WTEXT   equ 0x2500000
LINKS   equ 0x2600000
WSZ     equ 24
BCW     equ 700
BCTOP   equ 38
BCH     equ 480
ACOL    equ 0x1A5FD0
HCOL    equ 0x20243A
TCOL    equ 0x30344A

parse_url:
    mov esi, b_addr
    cmp dword [esi], 'http'
    jne .h
    cmp dword [esi+4], 's://'
    je .tls
    cmp dword [esi+3], 'p://'
    jne .h
    add esi, 7
.h:
    mov edi, b_host
.c:
    lodsb
    cmp al, '/'
    je .p
    test al, al
    jz .e
    stosb
    jmp .c
.e:
    xor al, al
    stosb
    mov word [b_path], '/'
    xor eax, eax
    ret
.p:
    xor al, al
    stosb
    dec esi
    mov edi, b_path
    call scopy
    xor al, al
    stosb
    xor eax, eax
    ret
.tls:
    mov eax, e_tls
    ret

; follows 3 redirects max
browser_go:
    mov dword [b_go], 0
    mov dword [b_redir], 0
.again:
    call parse_url
    test eax, eax
    jnz .err
    call net_get
    test eax, eax
    jnz .err
    mov esi, PAGE
    mov ecx, [pagelen]
    mov byte [esi+ecx], 0
    cmp byte [esi+9], '3' ; 3xx?
    jne .body
    call find_location
    test eax, eax
    jz .body
    cmp dword [eax], 'http'
    jne .body
    cmp byte [eax+4], 's'
    je .tlsredir
    inc dword [b_redir]
    cmp dword [b_redir], 3
    ja .body
    mov esi, eax
    mov edi, b_addr
.cp:
    lodsb
    cmp al, 13
    je .cpe
    stosb
    jmp .cp
.cpe:
    mov byte [edi], 0
    mov ecx, 0
    jmp .again
.tlsredir:
    mov eax, e_tls
    jmp .err
.body:
    mov esi, PAGE
.b:
    cmp byte [esi], 0
    je .none
    cmp dword [esi], 0x0A0D0A0D
    je .bf
    inc esi
    jmp .b
.bf:
    add esi, 4
.none:
    mov dword [b_status], s_done
    call layout
    mov dword [dirty], 1
    ret
.err:
    mov [b_status], eax
    mov dword [dirty], 1
    ret

find_location:
    mov esi, PAGE
.l:
    cmp byte [esi], 0
    je .no
    cmp dword [esi], 0x0A0D0A0D
    je .no
    mov eax, [esi]
    or eax, 0x20202020
    cmp eax, 'loca'
    jne .n
    mov eax, [esi+4]
    or eax, 0x20202020
    cmp eax, 'tion'
    jne .n
    cmp byte [esi+8], ':'
    jne .n
    lea eax, [esi+9]
.sp:
    cmp byte [eax], ' '
    jne .x
    inc eax
    jmp .sp
.n:
    inc esi
    jmp .l
.no:
    xor eax, eax
.x:
    ret

newline:
    cmp dword [l_x], 0
    je .x
    mov dword [l_x], 0
    add dword [l_y], 22
.x:
    ret

gapline:
    call newline
    add dword [l_y], 10
    ret

flush:
    push esi
    push eax
    mov edi, [l_wp]
    cmp edi, [l_ws]
    je .x
    mov byte [edi], 0
    inc edi
    mov [l_wp], edi
    mov esi, [l_ws]
    call twidth
    mov ebx, eax
    add eax, [l_x]
    cmp eax, BCW
    jbe .fit
    cmp dword [l_x], 0
    je .fit
    call newline
.fit:
    mov edi, [l_n]
    imul edi, WSZ
    add edi, WORDS
    mov eax, [l_x]
    mov [edi], eax
    mov eax, [l_y]
    mov [edi+4], eax
    mov [edi+8], esi
    mov [edi+12], ebx
    mov eax, [l_link]
    mov [edi+16], eax
    mov eax, [l_head]
    mov [edi+20], eax
    inc dword [l_n]
    lea eax, [ebx+4]
    add [l_x], eax
    mov eax, [l_wp]
    mov [l_ws], eax
.x:
    pop eax
    pop esi
    ret

tagis:
    push esi
    push edi
    mov edi, l_tag
.l:
    mov al, [esi]
    test al, al
    jz .end
    cmp al, [edi]
    jne .x
    inc esi
    inc edi
    jmp .l
.end:
    cmp byte [edi], 0
.x:
    pop edi
    pop esi
    ret

; no css, no images
layout:
    mov dword [l_x], 0
    mov dword [l_y], 0
    mov dword [l_n], 0
    mov dword [l_link], -1
    mov dword [l_head], 0
    mov dword [l_nl], 0
    mov dword [b_scroll], 0
    mov dword [l_ws], WTEXT
    mov dword [l_wp], WTEXT
.c:
    lodsb
    test al, al
    jz .done
    cmp al, '<'
    je .tag
    cmp al, '&'
    je .ent
    cmp al, ' '
    jbe .ws
    cmp al, 127
    jae .c
.put:
    mov edi, [l_wp]
    stosb
    mov [l_wp], edi
    jmp .c
.ws:
    call flush
    jmp .c
.done:
    call flush
    mov eax, [l_y]
    add eax, 40
    mov [b_doch], eax
    ret
.ent:
    mov eax, [esi]
    cmp eax, 'amp;'
    je .amp
    and eax, 0xFFFFFF
    cmp eax, 'lt;'
    je .lt
    cmp eax, 'gt;'
    je .gt
    mov eax, [esi]
    cmp eax, 'nbsp'
    je .nb
    mov al, '&'
    jmp .put
.amp:
    add esi, 4
    mov al, '&'
    jmp .put
.lt:
    add esi, 3
    mov al, '<'
    jmp .put
.gt:
    add esi, 3
    mov al, '>'
    jmp .put
.nb:
    add esi, 5
    jmp .ws
.tag:
  ; script/style/title get skipped
    call flush
    xor ebx, ebx
    cmp byte [esi], '/'
    jne .nm
    inc esi
    mov ebx, 1
.nm:
    mov edi, l_tag
    mov ecx, 9
.n:
    mov al, [esi]
    cmp al, ' '
    jbe .ne
    cmp al, '>'
    je .ne
    cmp al, '/'
    je .ne
    or al, 0x20
    stosb
    inc esi
    dec ecx
    jnz .n
.ne:
    mov byte [edi], 0
    push esi
    mov esi, t_script
    call tagis
    pop esi
    je .skip
    push esi
    mov esi, t_style
    call tagis
    pop esi
    je .skip
    push esi
    mov esi, t_title
    call tagis
    pop esi
    je .skip
    cmp byte [l_tag], 'h'
    jne .nh
    mov al, [l_tag+1]
    cmp al, '1'
    jb .nh
    cmp al, '6'
    ja .nh
    call gapline
    mov eax, 1
    sub eax, ebx
    mov [l_head], eax
    jmp .end
.nh:
    cmp word [l_tag], 'a'
    je .anchor
    push esi
    mov esi, blocks
.bl:
    cmp byte [esi], 0
    je .blx
    call tagis
    je .blk
.bs:
    lodsb
    test al, al
    jnz .bs
    jmp .bl
.blk:
    pop esi
    call newline
    jmp .end
.blx:
    pop esi
.end:
    lodsb
    test al, al
    jz .done
    cmp al, '>'
    jne .end
    jmp .c
.skip:
    test ebx, ebx
    jnz .end
.sk:
    lodsb
    test al, al
    jz .done
    cmp al, '<'
    jne .sk
    cmp byte [esi], '/'
    jne .sk
    jmp .end
.anchor:
    test ebx, ebx
    jz .open
    mov dword [l_link], -1
    jmp .end
.open:
    mov eax, [esi]
    cmp al, '>'
    je .end
    or eax, 0x20202000
    cmp eax, 0x65726820
    je .h1
    cmp eax, 0x65726809
    je .h1
    inc esi
    jmp .open
.h1:
    mov eax, [esi+1]
    or eax, 0x00202020
    add esi, 5
.q:
    lodsb
    cmp al, '>'
    je .c
    test al, al
    jz .done
    cmp al, 34
    je .val
    cmp al, 39
    jne .q
.val:
    mov bl, al
    mov edi, [l_nlink]
    mov eax, edi
    inc eax
    cmp eax, 200
    jae .end
    mov [l_nlink], eax
    mov [l_link], edi
    shl edi, 7
    add edi, LINKS
    mov ecx, 126
.v:
    lodsb
    cmp al, bl
    je .ve
    test al, al
    jz .ve
    stosb
    dec ecx
    jnz .v
.ve:
    mov byte [edi], 0
    jmp .end

;8 deep
push_history:
    pushad
    mov eax, [b_hist]
    cmp eax, 8
    jae .x
    shl eax, 7
    lea edi, [b_stack+eax]
    mov esi, b_addr
    call scopy
    xor al, al
    stosb
    inc dword [b_hist]
.x:
    popad
    ret

follow:
    cmp dword [esi], 'http'
    je .abs
    call push_history
    mov edi, b_addr
    push esi
    mov esi, b_url
    mov dword [b_url], 'http'
    mov dword [b_url+4], '://'
    call scopy
    mov esi, b_host
    call scopy
    pop esi
    cmp byte [esi], '/'
    je .tail
    push esi
    mov esi, b_path
    mov edx, esi
.f:
    lodsb
    test al, al
    jz .fe
    cmp al, '/'
    jne .f
    mov edx, esi
    jmp .f
.fe:
    mov esi, b_path
.cp:
    cmp esi, edx
    jae .cd
    movsb
    jmp .cp
.cd:
    pop esi
.tail:
    call scopy
    xor al, al
    stosb
    jmp start_load
.abs:
    call push_history
    mov edi, b_addr
    call scopy
    xor al, al
    stosb

start_load:
    mov edi, b_addr
    or ecx, -1
    xor al, al
    repne scasb
    not ecx
    dec ecx
    mov [b_len], ecx
    mov dword [b_status], s_load
    mov dword [l_nlink], 0
    mov dword [b_go], 1
    mov dword [dirty], 1
    ret

key_browser:
    cmp ebx, 0x48 ; up
    je .up
    cmp ebx, 0x50		;down
    je .dn
    cmp ebx, 0x49	;  pgup
    je .pu
    cmp ebx, 0x51  ;pgdn
    je .pd
    cmp al, 10
    je .go
    mov edi, b_addr
    mov ebx, b_len
    mov ecx, 120
    jmp edit_key
.go:
    call push_history
    jmp start_load
.up:
    mov eax, -44
    jmp scroll
.dn:
    mov eax, 44
    jmp scroll
.pu:
    mov eax, -400
    jmp scroll
.pd:
    mov eax, 400

scroll:
    add eax, [b_scroll]
    mov ecx, [b_doch]
    sub ecx, BCH
    cmp eax, ecx
    jle .a
    mov eax, ecx
.a:
    cmp eax, 0
    jge .b
    xor eax, eax
.b:
    mov [b_scroll], eax
    mov dword [dirty], 1
    ret

click_browser:
    cmp edx, 32
    jae .page
    cmp ecx, 40
    jae .x
    mov eax, [b_hist]
    test eax, eax
    jz .x
    dec eax
    mov [b_hist], eax
    shl eax, 7
    lea esi, [b_stack+eax]
    mov edi, b_addr
    call scopy
    xor al, al
    stosb
    jmp start_load
.page:
    cmp ecx, BCW+8
    jb .link
    mov eax, 400
    cmp edx, BCTOP+BCH/2
    jae scroll
    mov eax, -400
    jmp scroll
.link:
    sub ecx, 10
    sub edx, BCTOP
    add edx, [b_scroll]
    mov esi, WORDS
    mov ebp, [l_n]
    test ebp, ebp
    jz .x
.w:
    cmp dword [esi+16], 0
    jl .n
    mov eax, edx
    sub eax, [esi+4]
    cmp eax, 20
    jae .n
    mov eax, ecx
    sub eax, [esi]
    cmp eax, [esi+12]
    jae .n
    mov esi, [esi+16]
    shl esi, 7
    add esi, LINKS
    jmp follow
.n:
    add esi, WSZ
    dec ebp
    jnz .w
.x:
    ret

draw_browser:
    pushad
    mov eax, [cx0]
    add eax, 4
    mov ebx, [cy0]
    add ebx, 2
    mov ecx, 34
    mov edx, 26
    mov esi, 0xDDE3F4
    call rbox
    add eax, 13
    add ebx, 4
    mov esi, s_back
    mov edx, HCOL
    call text
    mov eax, [cx0]
    add eax, 44
    mov ebx, [cy0]
    add ebx, 2
    mov ecx, 500
    mov edx, 26
    mov esi, 0xFFFFFF
    call rbox
    add eax, 10
    add ebx, 4
    mov esi, b_addr
    mov edx, HCOL
    call text
    mov esi, [b_status]
    mov eax, [cx0]
    add eax, 556
    mov edx, 0x565C74
    call text
    mov eax, [cx0]
    mov ebx, [cy0]
    add ebx, 32
    mov ecx, 728
    mov edx, BCH+10
    mov esi, 0xFFFFFF
    call rect
    mov esi, WORDS
    mov ebp, [l_n]
    test ebp, ebp
    jz .bar
.w:
    mov ebx, [esi+4]
    sub ebx, [b_scroll]
    cmp ebx, BCH-20
    jae .n
    add ebx, [cy0]
    add ebx, BCTOP
    mov eax, [esi]
    add eax, [cx0]
    add eax, 10
    mov edx, TCOL
    cmp dword [esi+20], 0
    je .nh
    mov edx, HCOL
.nh:
    cmp dword [esi+16], 0
    jl .nl
    mov edx, ACOL
.nl:
    push esi
    mov ecx, [esi+12]
    mov edi, [esi+20]
    mov esi, [esi+8]
    call text
    test edi, edi
    jz .plain
    inc eax
    call text
    dec eax
.plain:
    pop esi
    cmp dword [esi+16], 0
    jl .n
    push esi
    add ebx, 16
    mov edx, 1
    mov esi, ACOL
    call rect
    pop esi
.n:
    add esi, WSZ
    dec ebp
    jnz .w
.bar:
    ; scrollbar
    mov eax, [b_doch]
    cmp eax, BCH
    jle .x
    mov eax, [b_scroll]
    imul eax, BCH-60
    mov ecx, [b_doch]
    sub ecx, BCH
    xor edx, edx
    div ecx
    mov ebx, eax
    add ebx, [cy0]
    add ebx, BCTOP
    mov eax, [cx0]
    add eax, 716
    mov ecx, 8
    mov edx, 60
    mov esi, 0xB0B6C8
    call rbox
.x:
    popad
    ret

browser_init:
    mov esi, b_home
    mov edi, PAGE
    call scopy
    xor al, al
    stosb
    mov esi, PAGE
    mov dword [l_nlink], 0
    call layout
    ret

b_go     dd 0
b_redir  dd 0
b_len    dd 12
b_doch   dd 0
b_scroll dd 0
b_hist   dd 0
b_status dd s_ready
l_x      dd 0
l_y      dd 0
l_n      dd 0
l_ws     dd 0
l_wp     dd 0
l_link   dd -1
l_nlink  dd 0
l_head   dd 0
l_nl     dd 0
l_tag    times 12 db 0
b_url    times 8 db 0
b_addr   db 'info.cern.ch'
         times 116 db 0
b_host   times 128 db 0
b_path   times 256 db 0
b_stack  times 8*128 db 0
t_script db 'script', 0
t_style  db 'style', 0
t_title  db 'title', 0
blocks   db 'p', 0, 'br', 0, 'div', 0, 'li', 0, 'ul', 0, 'ol', 0, 'tr', 0, 'dt', 0, 'dd', 0, 'hr', 0, 'pre', 0, 'center', 0, 'table', 0, 0
s_ready  db 'Ready', 0
s_load   db 'Loading...', 0
s_done   db 'Done', 0
s_back   db '<', 0
e_tls    db 'This site needs HTTPS', 0
b_home   db '<h1>XD Browser</h1><p>A web browser in a few kilobytes of assembly.</p>'
         db '<p>Type a site and press Enter. Up and Down scroll.</p>'
         db '<p><a href="http://info.cern.ch/">The first website</a></p>'
         db '<p><a href="http://example.com/">example.com</a></p>'
         db '<p><a href="http://neverssl.com/">neverssl.com</a></p>', 0
