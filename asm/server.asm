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
extern read_request
extern parse_request
extern parse_headers
extern print_request_info
extern create_thread
extern route_request
extern send_payments_response
;extern redis_publish_hello

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
	cmp rax, 1
	je .route_handled
	
	; Default route - unhandled
	;call redis_publish_hello ; Publish to Redis
	call timer_sleep        ; Keep existing delay
	call send_response      ; Send HTTP response
	jmp .close
	
.route_handled:
	; Specific route handled - send custom response
	call send_payments_response
	
.close:
	call close_connection   ; Close socket
	ret
