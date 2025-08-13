%include "asm/include/syscalls.inc"

%define AF_INET 2
%define SOCK_STREAM 1
%define SOCK_PROTOCOL 0
%define CR 0xD
%define LF 0xA

section .data
; Redis server address (localhost:6379)
redis_sockaddr:
	sa_family: dw AF_INET       ; 2 bytes
	port: dw 0xEB18             ; 2 bytes - 6379 in network byte order
	ip_addr: dd 0x0100007F      ; 4 bytes - 127.0.0.1 in network byte order
	sin_zero: dq 0              ; 8 bytes

; RESP protocol message for "PUBLISH channel hello"
redis_publish_msg:
	db "*3", CR, LF             ; *3\r\n (3 elements)
	db "$7", CR, LF             ; $7\r\n (PUBLISH length)
	db "PUBLISH", CR, LF        ; PUBLISH\r\n
	db "$7", CR, LF             ; $7\r\n (channel length)
	db "channel", CR, LF        ; channel\r\n
	db "$5", CR, LF             ; $5\r\n (message length)
	db "hello", CR, LF          ; hello\r\n
redis_msg_len: equ $ - redis_publish_msg

section .bss
redis_sockfd: resb 8            ; Redis socket file descriptor

section .text
global redis_connect
global redis_publish_hello
global redis_disconnect

redis_connect:
	; Create client socket
	mov rdi, AF_INET
	mov rsi, SOCK_STREAM
	mov rdx, SOCK_PROTOCOL
	mov rax, SYS_socket
	syscall
	
	; Check if socket creation failed
	cmp rax, 0
	jl .error
	mov [redis_sockfd], rax

	; Connect to Redis server
	mov rdi, [redis_sockfd]
	mov rsi, redis_sockaddr
	mov rdx, 16
	mov rax, SYS_connect
	syscall
	
	; Check if connection failed
	cmp rax, 0
	jl .error
	ret

.error:
	; Connection failed, close socket if it was created
	cmp qword [redis_sockfd], 0
	jle .skip_close
	mov rdi, [redis_sockfd]
	mov rax, SYS_close
	syscall
.skip_close:
	; Set socket to invalid value
	mov qword [redis_sockfd], -1
	ret

redis_disconnect:
	; Close Redis connection only if valid
	cmp qword [redis_sockfd], 0
	jle .skip_disconnect
	mov rdi, [redis_sockfd]
	mov rax, SYS_close
	syscall
.skip_disconnect:
	ret

redis_publish_hello:
	; Connect to Redis
	call redis_connect
	
	; Check if connection succeeded
	cmp qword [redis_sockfd], -1
	je .failed
	
	; Send PUBLISH command
	mov rdi, [redis_sockfd]
	mov rsi, redis_publish_msg
	mov rdx, redis_msg_len
	mov rax, SYS_write
	syscall

	; Disconnect from Redis
	call redis_disconnect
	ret

.failed:
	; Redis connection failed, just return (don't crash the server)
	ret