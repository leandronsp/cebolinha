%include "asm/include/syscalls.inc"

%define CR 0xD
%define LF 0xA

section .bss
request_buffer: resb 1024    ; Buffer to store incoming request
verb_ptr: resq 1              ; Pointer to verb start
verb_len: resq 1              ; Length of verb
path_ptr: resq 1              ; Pointer to path start
path_len: resq 1              ; Length of path
content_length_value: resq 1  ; Store the actual content length number
headers_start_ptr: resq 1     ; Pointer to start of headers (after headline CRLF)
body_ptr: resq 1              ; Pointer to body start
body_len: resq 1              ; Length of body (copy of content_length_value)

section .data
debug_verb_msg: db "Verb: "
debug_verb_msg_len: equ $ - debug_verb_msg
debug_path_msg: db "Path: "
debug_path_msg_len: equ $ - debug_path_msg
newline: db 10
content_length_header: db "Content-Length:"
content_length_header_len: equ $ - content_length_header
response:
	headline: db "HTTP/1.1 200 OK", CR, LF
	content_type: db "Content-Type: text/html", CR, LF
	content_length: db "Content-Length: 22", CR, LF
	crlf: db CR, LF
	body: db "<h1>Hello, World!</h1>"
responseLen: equ $ - response

; 404 Not Found response
not_found_response:
	db "HTTP/1.1 404 Not Found", CR, LF
	db "Content-Type: application/json", CR, LF
	db "Content-Length: 22", CR, LF
	db CR, LF
	db '{"error":"Not Found"}'
not_found_response_len: equ $ - not_found_response

section .text
global send_response
global send_not_found_response
global close_connection
global read_request
global parse_request
global print_request_info
global parse_headers
global verb_ptr
global verb_len
global path_ptr
global path_len
global body_ptr
global body_len

send_response:
	; fd is in r10
	mov rdi, r10
	mov rsi, response
	mov rdx, responseLen
	mov rax, SYS_write
	syscall
	ret

send_not_found_response:
	; fd is in r10
	mov rdi, r10
	mov rsi, not_found_response
	mov rdx, not_found_response_len
	mov rax, SYS_write
	syscall
	ret

close_connection:
	; fd is in r10
	mov rdi, r10
	mov rax, SYS_close
	syscall
	ret

read_request:
	; fd is in r10
	push r10
	mov rdi, r10                  ; fd
	mov rsi, request_buffer       ; buffer
	mov rdx, 1024                 ; max bytes to read
	mov rax, SYS_read
	syscall
	pop r10
	ret

parse_request:
	; Parse the HTTP request headline
	; Format: VERB PATH HTTP/1.1\r\n
	push rbx
	push rcx

	; Set verb_ptr to start of buffer
	mov rax, request_buffer
	mov [verb_ptr], rax

	; Find first space (end of verb)
	mov rsi, request_buffer
	xor rcx, rcx
.find_verb_end:
	mov al, [rsi]
	cmp al, ' '
	je .found_verb_end
	inc rsi
	inc rcx
	jmp .find_verb_end

.found_verb_end:
	; Store verb length
	mov [verb_len], rcx

	; Skip the space, set path_ptr
	inc rsi
	mov [path_ptr], rsi

	; Find second space or CR (end of path)
	xor rcx, rcx
.find_path_end:
	mov al, [rsi]
	cmp al, ' '
	je .found_path_end
	cmp al, CR
	je .found_path_end
	inc rsi
	inc rcx
	jmp .find_path_end

.found_path_end:
	; Store path length
	mov [path_len], rcx

	; Skip to end of headline (find LF after CR)
.skip_to_headers:
	mov al, [rsi]
	cmp al, LF
	je .found_headline_end
	inc rsi
	jmp .skip_to_headers

.found_headline_end:
	inc rsi                    ; Skip the LF
	mov [headers_start_ptr], rsi  ; Save headers start position

	pop rcx
	pop rbx
	ret

parse_headers:
	push rbx
	push rcx
	push rdx
	push rdi
	push rsi
	
	mov rbx, [headers_start_ptr]
	mov qword [content_length_value], 0  ; Initialize to 0
	
.next_header:
	; Check if we hit empty line (CRLF CRLF = end of headers)
	mov al, [rbx]
	cmp al, CR
	jne .check_content_length
	mov al, [rbx + 1]
	cmp al, LF
	jne .check_content_length
	
	; Found end of headers
	jmp .headers_done
	
.check_content_length:
	; Use repe cmpsb to compare "Content-Length:"
	mov rdi, rbx                        ; current header line
	mov rsi, content_length_header      ; target string
	mov rcx, content_length_header_len  ; string length
	repe cmpsb
	je .found_content_length           ; strings match
	
.skip_line:
	; Skip to next line
	mov al, [rbx]
	cmp al, LF
	je .next_line
	inc rbx
	jmp .skip_line
	
.next_line:
	inc rbx                 ; Skip LF
	jmp .next_header
	
.found_content_length:
	; rbx points after "Content-Length:"
	mov rbx, rdi            ; rdi was advanced by repe cmpsb
	
	; Skip spaces
.skip_spaces:
	mov al, [rbx]
	cmp al, ' '
	jne .parse_number
	inc rbx
	jmp .skip_spaces
	
.parse_number:
	xor rax, rax            ; Clear accumulator
	xor rcx, rcx            ; Clear temp
	
.digit_loop:
	mov cl, [rbx]
	cmp cl, '0'
	jl .number_done
	cmp cl, '9'
	jg .number_done
	
	sub cl, '0'            ; Convert ASCII to number
	imul rax, 10           ; Multiply current by 10
	add rax, rcx           ; Add new digit
	inc rbx
	jmp .digit_loop
	
.number_done:
	mov [content_length_value], rax
	jmp .skip_line         ; Continue parsing other headers
	
.headers_done:
debug:
	; rbx points to CR of empty line (CRLF CRLF)
	; Body starts after the CRLF
	add rbx, 2              ; Skip CRLF
	mov [body_ptr], rbx     ; Save body start pointer
	mov rax, [content_length_value]
	mov [body_len], rax     ; Save body length
	
	pop rsi
	pop rdi
	pop rdx
	pop rcx
	pop rbx
	ret

print_request_info:
	push r10

	; Print "Verb: "
	mov rdi, 1                    ; stdout
	mov rsi, debug_verb_msg
	mov rdx, debug_verb_msg_len
	mov rax, SYS_write
	syscall

	; Print the verb
	mov rdi, 1                    ; stdout
	mov rsi, [verb_ptr]
	mov rdx, [verb_len]
	mov rax, SYS_write
	syscall

	; Print newline
	mov rdi, 1                    ; stdout
	mov rsi, newline
	mov rdx, 1
	mov rax, SYS_write
	syscall

	; Print "Path: "
	mov rdi, 1                    ; stdout
	mov rsi, debug_path_msg
	mov rdx, debug_path_msg_len
	mov rax, SYS_write
	syscall

	; Print the path
	mov rdi, 1                    ; stdout
	mov rsi, [path_ptr]
	mov rdx, [path_len]
	mov rax, SYS_write
	syscall

	; Print newline
	mov rdi, 1                    ; stdout
	mov rsi, newline
	mov rdx, 1
	mov rax, SYS_write
	syscall

	pop r10
	ret
