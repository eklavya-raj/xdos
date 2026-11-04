TCOLS equ 78
TROWS equ 24

draw_sys:
    mov eax, [cx0]
    add eax, 14
    mov ebx, [cy0]
    add ebx, 14
    xor edi, edi
    mov ebp, 1
    call cicon
    mov eax, [cx0]
    add eax, 80
    mov ebx, [cy0]
    add ebx, 14
    mov edx, 0x20243A
    mov esi, s_name
    call text
    add ebx, 24
    mov edx, 0x565C74
    mov esi, s_i1
    call text
    add ebx, 22
    mov esi, s_i2
    call text
    add ebx, 22
    mov esi, s_i3
    call text
    add ebx, 22
    mov esi, s_i4
    call text
    push eax
    call twidth
    mov ecx, eax
    pop eax
    add eax, ecx
    add eax, 4
    push eax
    mov eax, [packed]
    call itoa
    pop eax
    call text
    ret

term_init:
    mov edi, TBUF
    mov ecx, TROWS*TCOLS
    xor al, al
    rep stosb
    and dword [tcol], 0
    and dword [trow], 0
    mov esi, s_tbanner
    call tputs
    jmp prompt

prompt:
    mov esi, s_prompt
    jmp tputs

tputc:
    pushad
    cmp al, 10
    je .nl
    cmp al, 8
    je .bs
    imul edi, [trow], TCOLS
    add edi, [tcol]
    mov [TBUF+edi], al
    inc dword [tcol]
    cmp dword [tcol], TCOLS
    jb .x
.nl:
    and dword [tcol], 0
    inc dword [trow]
    cmp dword [trow], TROWS
    jb .x
    mov esi, TBUF+TCOLS
    mov edi, TBUF
    mov ecx, (TROWS-1)*TCOLS
    rep movsb
    mov ecx, TCOLS
    xor al, al
    rep stosb
    mov dword [trow], TROWS-1
    jmp .x
.bs:
    cmp dword [tcol], 0
    je .x
    dec dword [tcol]
    imul edi, [trow], TCOLS
    add edi, [tcol]
    mov byte [TBUF+edi], 0
.x:
    popad
    ret

tputs:
    pushad
.l:
    lodsb
    test al, al
    jz .x
    call tputc
    jmp .l
.x:
    popad
    ret

tnum:
    pushad
    call itoa
    call tputs
    popad
    ret

draw_term:
    mov eax, [cx0]
    mov ebx, [cy0]
    mov esi, [cur]
    mov ecx, [esi+WW]
    sub ecx, 12
    mov edx, [esi+WH]
    sub edx, 36
    mov esi, 0x10121E
    call rect
    xor ebp, ebp
    mov edx, 0x7CF0A8
.r:
    xor edi, edi
.c:
    imul esi, ebp, TCOLS
    add esi, edi
    movzx ecx, byte [TBUF+esi]
    test ecx, ecx
    jz .n
    mov eax, edi
    shl eax, 3
    add eax, [cx0]
    mov ebx, ebp
    shl ebx, 4
    add ebx, [cy0]
    call glyph
.n:
    inc edi
    cmp edi, TCOLS
    jb .c
    inc ebp
    cmp ebp, TROWS
    jb .r
    mov eax, [tcol]
    shl eax, 3
    add eax, [cx0]
    mov ebx, [trow]
    shl ebx, 4
    add ebx, [cy0]
    add ebx, 13
    mov ecx, 8
    mov edx, 2
    mov esi, 0x7CF0A8
    call rect
    ret

key_term:
    cmp al, 10
    je .run
    mov edi, tline
    mov ebx, tlen
    mov ecx, 70
    push eax
    call edit_key
    pop eax
    jnc tputc
    ret
.run:
    call tputc
    call exec
    and dword [tlen], 0
    mov byte [tline], 0
    jmp prompt

; cut at first space
split:
    lodsb
    test al, al
    jz .end
    cmp al, ' '
    jne split
    mov byte [esi-1], 0
    ret
.end:
    dec esi
    ret

exec:
    cmp byte [tline], 0
    je .x
    mov esi, tline
    call split
    mov [targ], esi
    mov esi, tline
    mov ebx, cmdtab
.l:
    mov edi, [ebx]
    test edi, edi
    jz .bad
    call strcmp
    je .hit
    add ebx, 8
    jmp .l
.hit:
    jmp [ebx+4]
.bad:
    mov esi, s_bad
    jmp tputs
.x:
    ret

c_help:
    mov esi, s_help
    jmp tputs

c_ver:
    mov esi, s_ver
    call tputs
    mov eax, [packed]
    call tnum
    mov esi, s_verb
    jmp tputs

c_echo:
    mov esi, [targ]
    call tputs
    mov al, 10
    jmp tputc

c_clear:
    mov edi, TBUF
    mov ecx, TROWS*TCOLS
    xor al, al
    rep stosb
    and dword [tcol], 0
    and dword [trow], 0
    ret

c_time:
    mov esi, clock
    call tputs
    mov al, 10
    jmp tputc

c_ls:
    xor ebx, ebx
.l:
    mov eax, ebx
    call fs_entry
    mov esi, eax
    cmp dword [esi+28], 0
    je .n
    call tputs
    mov al, ' '
    call tputc
    call tputc
    mov eax, [esi+24]
    call tnum
    mov esi, s_bytes
    call tputs
.n:
    inc ebx
    cmp ebx, FSMAX
    jb .l
    ret

c_cat:
    mov esi, [targ]
    call fs_find
    cmp eax, 0
    jl .no
    mov ebx, eax
    call fs_entry
    mov ecx, [eax+24]
    mov eax, ebx
    call fs_data
    mov esi, eax
    jecxz .end
.l:
    lodsb
    call tputc
    dec ecx
    jnz .l
.end:
    mov al, 10
    jmp tputc
.no:
    mov esi, s_nofile
    jmp tputs

c_rm:
    mov esi, [targ]
    call fs_find
    cmp eax, 0
    jl c_cat.no
    call fs_delete
    cmp eax, [notefile]
    jne .x
    or dword [notefile], -1
.x:
    ret

c_mv:
    mov esi, [targ]
    call split
    mov edi, esi
    mov esi, [targ]
    call fs_find
    test eax, eax
    js c_cat.no
    mov esi, edi
    call fs_rename
    jnc .x
    mov esi, s_rename_bad
    call tputs
    mov al, 10
    jmp tputc
.x:
    ret

;write <file> <text>
c_write:
    mov esi, [targ]
    cmp byte [esi], 0
    je c_cat.no
    call split
    mov ebx, esi
    mov esi, [targ]
    call fs_find
    cmp eax, 0
    jge .have
    call fs_create
    cmp eax, 0
    jl .full
.have:
    mov esi, ebx
    xor ecx, ecx
.len:
    cmp byte [esi+ecx], 0
    je .go
    inc ecx
    jmp .len
.go:
    call fs_write
    mov esi, s_saved
    jmp tputs
.full:
    mov esi, s_full
    jmp tputs

c_curl:
    mov esi, s_busy
    cmp dword [co_on], 0
    jne tputs
    mov esi, [targ]
    mov edi, c_url
    call scopy
    stosb
    mov eax, curl_job
    call co_start
    pop eax
    and dword [tlen], 0
    mov byte [tline], 0
    ret

c_run:
    mov esi, [targ]
    xor ebx, ebx
.l:
    mov edi, [titles+ebx*4]
    call strcmp
    je .hit
    inc ebx
    cmp ebx, NWIN
    jb .l
    mov esi, s_noapp
    jmp tputs
.hit:
    mov eax, ebx
    jmp open

cmdtab:
    dd s_c1, c_help, s_c2, c_ls, s_c3, c_cat, s_c4, c_write, s_c5, c_rm, s_c6, c_echo
    dd s_c7, c_clear, s_c8, c_ver, s_c9, c_time, s_c10, c_run, s_c11, shutdown, s_mv, c_mv, s_curl, c_curl, 0, 0

s_c1    db 'help', 0
s_c2    db 'ls', 0
s_c3    db 'cat', 0
s_c4    db 'write', 0
s_c5    db 'rm', 0
s_c6    db 'echo', 0
s_c7    db 'clear', 0
s_c8    db 'ver', 0
s_c9    db 'time', 0
s_c10   db 'run', 0
s_c11   db 'shutdown', 0
s_mv    db 'mv', 0
s_curl  db 'curl', 0
s_busy  db 'Busy', 10, 0
s_prompt db 'xd> ', 0
s_tbanner db 'Type help', 10, 0
s_help  db 'ls cat write mv rm echo run curl time ver clear shutdown', 10, 0
s_bad   db 'Unknown', 10, 0
s_ver   db 'XD OS ', 0
s_verb  db ' of 16384', 10, 0
s_bytes db ' bytes', 10, 0
s_nofile db 'No file', 10, 0
s_noapp db 'No app', 10, 0
s_saved db 'Saved', 10, 0
s_full  db 'Full', 10, 0
s_i1    db 'x86 assembly', 0
s_i2    db '1024 x 768', 0
s_i3    db 'Files live in this image', 0
s_i4    db 'System bytes:', 0

tcol    dd 0
trow    dd 0
tlen    dd 0
targ    dd 0
tline   times 72 db 0

draw_note:
    mov eax, [cx0]
    add eax, 4
    mov ebx, [cy0]
    add ebx, 2
    mov ecx, 54
    mov edx, 24
    mov esi, 0xDDE3F4
    call rbox
    add eax, 60
    call rbox
    mov edx, 0x20243A
    sub eax, 48
    add ebx, 3
    mov esi, s_save
    call text
    add eax, 62
    mov esi, s_new
    call text
    add eax, 60
    mov edx, 0x565C74
    mov esi, s_unsaved
    mov ecx, [notefile]
    cmp ecx, 0
    jl .nm
    push eax
    mov eax, ecx
    call fs_entry
    mov esi, eax
    pop eax
.nm:
    call text
    mov eax, [cx0]
    add eax, 4
    mov ebx, [cy0]
    add ebx, 34
    mov [t_x], eax
    mov [t_y], eax
    xor esi, esi
    mov edx, 0x20243A
    xor ebp, ebp
.c:
    cmp esi, [notelen]
    jae .caret
    movzx ecx, byte [NOTE+esi]
    inc esi
    cmp cl, 10
    je .nl
    mov [t_x], eax
    call glyph
    mov eax, [t_x]
    add eax, 8
    inc ebp
    cmp ebp, 54
    jb .c
.nl:
    mov eax, [t_y]
    add ebx, 18
    xor ebp, ebp
    jmp .c
.caret:
    mov [t_x], eax
    mov ecx, '_'
    call glyph
    ret

key_note:
    mov edi, NOTE
    mov ebx, notelen
    mov ecx, 1000
    jmp edit_key

click_note:
    cmp edx, 28
    jae .x
    cmp ecx, 60
    jb note_save
    cmp ecx, 120
    jb note_new
.x:
    ret

note_new:
    and dword [notelen], 0
    or dword [notefile], -1
    ret

; note1.txt .. note9.txt
note_save:
    mov eax, [notefile]
    cmp eax, 0
    jge .have
    mov byte [newname+4], '1'
.t:
    mov esi, newname
    call fs_find
    cmp eax, 0
    jl .c
    inc byte [newname+4]
    cmp byte [newname+4], '9'
    jbe .t
    ret
.c:
    mov esi, newname
    call fs_create
    cmp eax, 0
    jl .x
    mov [notefile], eax
.have:
    mov esi, NOTE
    mov ecx, [notelen]
    call fs_write
.x:
    ret

note_open:
    mov [notefile], eax
    mov ebx, eax
    call fs_entry
    mov ecx, [eax+24]
    mov [notelen], ecx
    mov eax, ebx
    call fs_data
    mov esi, eax
    mov edi, NOTE
    rep movsb
    mov eax, A_NOTE
    jmp open

draw_files:
    xor ebp, ebp
    xor edi, edi
.l:
    mov eax, edi
    call fs_entry
    cmp dword [eax+28], 0
    je .n
    mov esi, eax
    mov eax, [cx0]
    add eax, 6
    imul ebx, ebp, 26
    add ebx, [cy0]
    add ebx, 4
    push ebp
    push edi
    mov ecx, 348
    mov edx, 24
    push esi
    mov esi, 0xE8ECF6
    call rbox
    pop esi
    add eax, 10
    add ebx, 3
    mov edx, 0x20243A
    call text
    add eax, 230
    push eax
    mov eax, [esi+24]
    call itoa
    pop eax
    mov edx, 0x565C74
    call text
    add eax, 76
    mov ecx, 'x'
    mov edx, 0xE5484D
    call glyph
    pop edi
    pop ebp
    inc ebp
.n:
    inc edi
    cmp edi, FSMAX
    jb .l
    ret

click_files:
    cmp ecx, 6
    jb .x
    cmp ecx, 354
    jae .x
    cmp edx, 4
    jb .x
    sub edx, 4
    mov eax, edx
    xor edx, edx
    mov ebx, 26
    div ebx
    cmp edx, 24
    jae .x
    mov edx, eax
    xor eax, eax
.l:
    push eax
    call fs_entry
    cmp dword [eax+28], 0
    pop eax
    je .n
    dec edx
    js .hit
.n:
    inc eax
    cmp eax, FSMAX
    jb .l
.x:
    ret
.hit:
    mov esi, m_file
    test ebp, ebp
    jnz ctx_show
    cmp ecx, 320
    jb note_open
    jmp file_delete

; uses the menu as a text box
file_rename:
    mov [file_slot], eax
    mov byte [file_mode], 2
    and dword [rename_len], 0
    mov byte [rename_name], 0
    mov esi, m_rename
    jmp ctx_show

file_delete:
    call fs_delete
    cmp eax, [notefile]
    jne .x
    or dword [notefile], -1
.x:
    ret

close_file_popup:
    mov byte [file_mode], 0
    and dword [ctx_items], 0
    ret

key_files:
    cmp bl, 1
    je close_file_popup
    cmp byte [file_mode], 2
    jb .x
    cmp al, 10
    je .commit
    mov edi, rename_name
    mov ebx, rename_len
    mov ecx, 23
    call edit_key
    jc .x
    mov byte [file_mode], 2
    mov dword [ctx_items], m_rename
.x:
    ret
.commit:
    mov eax, [file_slot]
    mov esi, rename_name
    call fs_rename
    jnc close_file_popup
    mov byte [file_mode], 3
    mov dword [ctx_items], m_bad
    ret

file_mode db 0                       ; closed, menu, rename, bad name
file_slot dd 0
rename_len dd 0
rename_name times 24 db 0
s_rename_prompt db 'New name (Enter)', 0
s_rename_bad db 'Invalid or taken', 0

draw_calc:
    mov eax, [cx0]
    add eax, 8
    mov ebx, [cy0]
    add ebx, 8
    mov ecx, 220
    mov edx, 50
    mov esi, 0x20243A
    call rbox
    mov eax, [c_cur]
    call itoa
    call twidth
    neg eax
    add eax, [cx0]
    add eax, 216
    mov ebx, [cy0]
    add ebx, 24
    mov edx, 0xFFFFFF
    call text
    xor ebp, ebp
.b:
    mov eax, ebp
    and eax, 3
    imul eax, 56
    add eax, [cx0]
    add eax, 8
    mov ebx, ebp
    shr ebx, 2
    imul ebx, 56
    add ebx, [cy0]
    add ebx, 66
    mov ecx, 52
    mov edx, 52
    mov esi, 0xDDE3F4
    mov edi, ebp
    and edi, 3
    cmp edi, 3
    jne .d
    mov esi, 0xF5A05A
.d:
    call rbox
    add eax, 22
    add ebx, 18
    movzx ecx, byte [c_keys+ebp]
    mov edx, 0x20243A
    call glyph
    inc ebp
    cmp ebp, 16
    jb .b
    ret

click_calc:
    sub edx, 66
    jb .x
    sub ecx, 8
    jb .x
    mov eax, edx
    xor edx, edx
    mov ebx, 56
    div ebx
    cmp eax, 4
    jae .x
    mov esi, eax
    mov eax, ecx
    xor edx, edx
    div ebx
    cmp eax, 4
    jae .x
    lea eax, [eax+esi*4]
    movzx eax, byte [c_keys+eax]
    cmp al, '0'
    jb .op
    cmp al, '9'
    ja .op
    sub eax, '0'
    cmp dword [c_fresh], 0
    je .digit
    and dword [c_cur], 0
    and dword [c_fresh], 0
.digit:
    imul ecx, [c_cur], 10
    add ecx, eax
    mov [c_cur], ecx
    ret
.op:
    cmp al, 'C'
    je .clear
    call calc_apply
    mov dword [c_fresh], 1
    cmp al, '='
    jne .keep
    xor eax, eax
.keep:
    mov [c_op], eax
    ret
.clear:
    xor eax, eax
    mov [c_cur], eax
    mov [c_acc], eax
    mov [c_op], eax
.x:
    ret

;div by 0=0
calc_apply:
    push eax
    mov eax, [c_acc]
    mov ecx, [c_cur]
    mov ebx, [c_op]
    cmp bl, '+'
    jne .a
    add eax, ecx
    jmp .s
.a:
    cmp bl, '-'
    jne .b
    sub eax, ecx
    jmp .s
.b:
    cmp bl, '*'
    jne .c
    imul eax, ecx
    jmp .s
.c:
    cmp bl, '/'
    jne .d
    test ecx, ecx
    jz .z
    cdq
    idiv ecx
    jmp .s
.z:
    xor eax, eax
    jmp .s
.d:
    mov eax, ecx
.s:
    mov [c_acc], eax
    mov [c_cur], eax
    pop eax
    ret

paint_stroke:
    movzx eax, byte [zord+NWIN-1]
    cmp eax, A_PAINT
    jne .out
    lea esi, [wins+A_PAINT*WSIZE]
    cmp dword [esi+WVIS], 1
    jne .out
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

paint_clear:
    mov edi, CANVAS
    mov ecx, CANW*CANH
    mov eax, 0xFFFFFF
    rep stosd
    ret

draw_paint:
    pushad
    mov ebp, CANH
    mov esi, CANVAS
    mov edx, [cy0]
.r:
    cmp edx, HEIGHT
    jae .n
    mov ecx, [cx0]
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
    imul eax, ebp, 30
    add eax, [cx0]
    mov ebx, [cy0]
    add ebx, CANH+6
    mov ecx, 26
    mov edx, 24
    mov esi, [swatches+ebp*4]
    call rbox
    inc ebp
    cmp ebp, 6
    jb .sw
    popad
    ret

notefile dd -1
notelen  dd 0
c_cur    dd 0
c_acc    dd 0
c_op     dd 0
c_fresh  dd 0
c_keys   db '789/456*123-C0=+'
newname  db 'note1.txt', 0
s_save   db 'Save', 0
s_new    db 'New', 0
s_unsaved db 'Unsaved', 0
