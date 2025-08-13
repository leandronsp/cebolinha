%include "asm/include/syscalls.inc"

section .data
timespec:
	tv_sec: dq 1
	tv_nsec: dq 0

section .text
global timer_sleep

timer_sleep:
	lea rdi, [timespec]
	mov rax, SYS_nanosleep
	syscall
	ret