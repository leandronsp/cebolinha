%include "asm/include/syscalls.inc"

%define CR 0xD
%define LF 0xA

section .data
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