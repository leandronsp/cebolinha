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
	mov [redis_sockfd], rax

	; Connect to Redis server
	mov rdi, [redis_sockfd]
	mov rsi, redis_sockaddr
	mov rdx, 16
	mov rax, SYS_connect
	syscall
	ret

redis_disconnect:
	; Close Redis connection
	mov rdi, [redis_sockfd]
	mov rax, SYS_close
	syscall
	ret

redis_publish_hello:
	; Connect to Redis
	call redis_connect

	; Send PUBLISH command
	mov rdi, [redis_sockfd]
	mov rsi, redis_publish_msg
	mov rdx, redis_msg_len
	mov rax, SYS_write
	syscall

	; Disconnect from Redis
	call redis_disconnect
	ret