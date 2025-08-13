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

%include "asm/include/syscalls.inc"
%include "asm/include/common.inc"

%define CHILD_STACK_SIZE 4096
%define CLONE_VM 0x00000100
%define CLONE_FS 0x00000200
%define CLONE_FILES 0x00000400
%define CLONE_PARENT 0x00008000
%define CLONE_THREAD 0x00010000
%define CLONE_IO 0x80000000
%define CLONE_SIGHAND 0x00000800

%define PROT_READ 0x1
%define PROT_WRITE 0x2
%define MAP_GROWSDOWN 0x100
%define MAP_ANONYMOUS 0x0020     
%define MAP_PRIVATE 0x0002      

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
	call thread        
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

thread:
	mov rdi, 0x0
	mov rsi, CHILD_STACK_SIZE
	mov rdx, PROT_WRITE | PROT_READ
	mov r10, MAP_ANONYMOUS | MAP_PRIVATE | MAP_GROWSDOWN
	mov rax, SYS_mmap
	syscall

	mov rdi, CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_PARENT|CLONE_THREAD|CLONE_IO
	lea rsi, [rax + CHILD_STACK_SIZE - 8]
	mov qword [rsi], handle
	mov rax, SYS_clone
	syscall
	ret

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
