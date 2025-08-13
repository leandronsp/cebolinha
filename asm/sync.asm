%include "asm/include/syscalls.inc"

%define FUTEX_WAIT 0
%define FUTEX_WAKE 1
%define FUTEX_PRIVATE_FLAG 128

section .data
mutex: dq 1
condvar: dq 0

section .text
global lock_mutex
global unlock_mutex
global emit_signal
global wait_condvar

lock_mutex:
   mov rax, 0
   xchg rax, [mutex]   
   test rax, rax       
   jnz .done           
   pause               
   jmp lock_mutex     
.done:
   ret

unlock_mutex:
   mov qword [mutex], 1  
   ret

emit_signal:
   mov rdi, condvar
   mov rsi, FUTEX_WAKE | FUTEX_PRIVATE_FLAG
   xor rdx, rdx
   xor r10, r10
   xor r8, r8
   mov rax, SYS_futex
   syscall
   ret

wait_condvar:
   mov rdi, condvar           
   mov rsi, FUTEX_WAIT | FUTEX_PRIVATE_FLAG 
   xor rdx, rdx
   xor r10, r10              
   xor r8, r8               
   mov rax, SYS_futex
   syscall
   test rax, rax
   jz .done_condvar
.done_condvar:
   ret
