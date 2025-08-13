%include "asm/include/syscalls.inc"

%define AF_INET 2
%define SOCK_STREAM 1
%define SOCK_PROTOCOL 0
%define BACKLOG 2

section .data
sockaddr:
	sa_family: dw AF_INET   ; 2 bytes
	port: dw 0xB80B         ; 2 bytes
	ip_addr: dd 0           ; 4 bytes
	sin_zero: dq 0          ; 8 bytes

section .bss
sockfd: resb 8

section .text
global sockfd
global create_socket
global bind_socket
global listen_socket
global accept_connection

create_socket:
	mov rdi, AF_INET
	mov rsi, SOCK_STREAM
	mov rdx, SOCK_PROTOCOL
	mov rax, SYS_socket
	syscall
	mov [sockfd], rax
	ret

bind_socket:
	mov rdi, [sockfd]
	mov rsi, sockaddr
	mov rdx, 16
	mov rax, SYS_bind
	syscall
	ret

listen_socket:
	mov rdi, [sockfd]
	mov rsi, BACKLOG
	mov rax, SYS_listen
	syscall
	ret

accept_connection:
	mov rdi, [sockfd]
	mov rsi, 0
	mov rdx, 0
	mov r10, 0
	mov rax, SYS_accept4
	syscall
	ret