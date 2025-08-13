global _start
extern timer_sleep
extern lock_mutex
extern unlock_mutex
extern emit_signal
extern wait_condvar
extern enqueue
extern dequeue
extern queuePtr
extern queueSize
extern queue
extern sockfd
extern create_socket
extern bind_socket
extern listen_socket
extern accept_connection
extern send_response
extern close_connection
extern create_thread

%include "asm/include/syscalls.inc"
%include "asm/include/common.inc"

section .bss

section .text
_start:
.initialize_queue:
	mov rdi, 0
	mov rax, SYS_brk
	syscall
	mov [queue], rax

	mov rdi, rax
	add rdi, QUEUE_OFFSET_CAPACITY
	mov rax, SYS_brk
	syscall
.initialize_pool:
	mov r8, 0
.pool:
	mov rdi, handle
	call create_thread
	inc r8
	cmp r8, 5
	je .socket
	jmp .pool
.socket:
	call create_socket
.bind:
	call bind_socket
.listen:
	call listen_socket
.accept:
	call accept_connection

	mov r8, rax
	call enqueue

	jmp .accept

handle:
	cmp byte [queuePtr], 0
	je .wait

	call dequeue
	mov r10, rax
	call action
	jmp handle
.wait:
	call wait_condvar
	jmp handle

action:
	call timer_sleep
	call send_response
	call close_connection
	ret
