%include "asm/include/syscalls.inc"
%include "asm/include/common.inc"

%define CR 0xD
%define LF 0xA

extern verb_ptr
extern verb_len
extern path_ptr
extern path_len
extern body_ptr
extern body_len

section .data
; Route matching strings
post_verb: db "POST"
post_verb_len: equ $ - post_verb
payments_path: db "/payments"
payments_path_len: equ $ - payments_path

; Payment success response (JSON)
payments_response:
	db "HTTP/1.1 200 OK", CR, LF
	db "Content-Type: application/json", CR, LF
	db "Content-Length: 23", CR, LF
	db CR, LF
	db '{"message":"enqueued"}'
payments_response_len: equ $ - payments_response

section .text
global route_request
global handle_post_payments
global send_payments_response

route_request:
	; Check if POST /payments
	call check_post_payments
	cmp rax, 1
	je handle_post_payments
	
	; Default: return 0 (not handled)
	xor rax, rax
	ret

check_post_payments:
	push rbx
	push rcx
	push rdi
	push rsi
	
	; Check verb == "POST"
	mov rdi, [verb_ptr]
	mov rsi, post_verb
	mov rcx, post_verb_len
	cmp rcx, [verb_len]
	jne .not_match
	repe cmpsb
	jne .not_match
	
	; Check path == "/payments"
	mov rdi, [path_ptr]
	mov rsi, payments_path
	mov rcx, payments_path_len
	cmp rcx, [path_len]
	jne .not_match
	repe cmpsb
	jne .not_match
	
	; Match found
	mov rax, 1
	jmp .done
	
.not_match:
	xor rax, rax
	
.done:
	pop rsi
	pop rdi
	pop rcx
	pop rbx
	ret

handle_post_payments:
	; Process payment (for now, just return success)
	; In future: parse JSON from body_ptr/body_len
	
	; Set response handled flag
	mov rax, 1  ; success
	ret

send_payments_response:
	; fd is in r10
	mov rdi, r10
	mov rsi, payments_response
	mov rdx, payments_response_len
	mov rax, SYS_write
	syscall
	ret
