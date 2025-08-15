global _start
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
extern send_not_found_response
extern close_connection
extern read_request
extern parse_request
extern parse_headers
extern print_request_info
extern create_thread
extern route_request
extern send_payments_response

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
	cmp r8, THREAD_POOL_SIZE
	je .socket
	jmp .pool

.socket:
	call create_socket
	call bind_socket
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
	call read_request       ; Read HTTP request
	call parse_request      ; Parse verb and path
	call parse_headers      ; Parse headers and body
	call print_request_info ; Print to stdout
	
	; Check for specific routes
	call route_request
	cmp rax, 0
	je .default_route
	
	; Specific route handled - rax contains Redis result (1=success, 2=error)
	; Send custom response based on Redis result
	call send_payments_response
	jmp .close
	
.default_route:
	; Default route - unhandled (404 Not Found)
	call send_not_found_response ; Send 404 response
	
.close:
	call close_connection   ; Close socket
	ret
