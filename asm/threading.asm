%include "asm/include/syscalls.inc"

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

section .text
global create_thread

; Creates a thread with given handler function
; Parameters: rdi = handler function address
; Returns: rax = thread ID (or error)
create_thread:
	push rdi  ; save handler address

	; Allocate stack for thread
	mov rdi, 0x0
	mov rsi, CHILD_STACK_SIZE
	mov rdx, PROT_WRITE | PROT_READ
	mov r10, MAP_ANONYMOUS | MAP_PRIVATE | MAP_GROWSDOWN
	mov rax, SYS_mmap
	syscall

	pop rdx  ; restore handler address

	; Setup thread stack with handler
	lea rsi, [rax + CHILD_STACK_SIZE - 8]
	mov qword [rsi], rdx

	; Create thread
	mov rdi, CLONE_VM|CLONE_FS|CLONE_FILES|CLONE_SIGHAND|CLONE_PARENT|CLONE_THREAD|CLONE_IO
	mov rax, SYS_clone
	syscall
	ret