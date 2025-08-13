%include "asm/include/syscalls.inc"

%define CR 0xD
%define LF 0xA

section .bss
request_buffer: resb 1024    ; Buffer to store incoming request
verb_ptr: resq 1              ; Pointer to verb start
verb_len: resq 1              ; Length of verb
path_ptr: resq 1              ; Pointer to path start
path_len: resq 1              ; Length of path

section .data
debug_verb_msg: db "Verb: "
debug_verb_msg_len: equ $ - debug_verb_msg
debug_path_msg: db "Path: "
debug_path_msg_len: equ $ - debug_path_msg
newline: db 10
response:
	headline: db "HTTP/1.1 200 OK", CR, LF
	content_type: db "Content-Type: text/html", CR, LF
	content_length: db "Content-Length: 22", CR, LF
	crlf: db CR, LF
	body: db "<h1>Hello, World!</h1>"
responseLen: equ $ - response

section .text
global send_response
global close_connection
global read_request
global parse_request
global print_request_info

send_response:
	; fd is in r10
	mov rdi, r10
	mov rsi, response
	mov rdx, responseLen
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
