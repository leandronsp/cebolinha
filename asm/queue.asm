%include "asm/include/syscalls.inc"

extern lock_mutex
extern unlock_mutex  
extern emit_signal

%define QUEUE_OFFSET_CAPACITY 5

section .data
queuePtr: db 0
queueSize: db QUEUE_OFFSET_CAPACITY

section .bss
queue: resb 8

section .text
global enqueue
global dequeue
global queuePtr
global queueSize
global queue

enqueue:
	call lock_mutex

	mov r9, [queueSize]
	cmp byte [queuePtr], r9b   ; check if queue is full
	je .resize

	xor rdx, rdx
	mov dl, [queuePtr]	
	mov [queue + rdx], r8	
	inc byte [queuePtr]
.done_enqueue:
	call emit_signal
	call unlock_mutex
	ret
.resize:
	mov r10, r8   ; preserve the RDI (element to be added to array)

	mov rdi, 0
	mov rax, SYS_brk
	syscall

	mov rdi, rax
	add rdi, QUEUE_OFFSET_CAPACITY
	mov rax, SYS_brk
	syscall

	mov r9, [queueSize]
	add r9, QUEUE_OFFSET_CAPACITY
	mov [queueSize], r9

	mov r8, r10
	jmp enqueue

dequeue:
	call lock_mutex
	xor rax, rax
	xor rsi, rsi

	mov al, [queue]
	mov rcx, 0
.loop_dequeue:
	cmp byte [queuePtr], 0
	je .return_dequeue

	cmp cl, [queuePtr]
	je .done_dequeue

	; shift
	xor r10, r10
	mov r10b, [queue + rcx + 1]
	mov byte [queue + rcx], r10b

	inc rcx
	jmp .loop_dequeue
.done_dequeue:
	dec byte [queuePtr]
.return_dequeue:
	call unlock_mutex
	ret