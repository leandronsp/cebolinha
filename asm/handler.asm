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
extern redis_publish_body
extern redis_query_summary
extern redis_response_buffer
extern parse_redis_responses
extern build_summary_json
extern summary_json_buffer

section .data
; Route matching strings
post_verb: db "POST"
post_verb_len: equ $ - post_verb
get_verb: db "GET"
get_verb_len: equ $ - get_verb
payments_path: db "/payments"
payments_path_len: equ $ - payments_path
payments_summary_path: db "/payments-summary"
payments_summary_path_len: equ $ - payments_summary_path

; Payment success response (JSON)
payments_success_response:
	db "HTTP/1.1 200 OK", CR, LF
	db "Content-Type: application/json", CR, LF
	db "Content-Length: 22", CR, LF
	db CR, LF
	db '{"message":"enqueued"}'
payments_success_len: equ $ - payments_success_response

; Payment Redis failure response (JSON)
payments_error_response:
	db "HTTP/1.1 500 Internal Server Error", CR, LF
	db "Content-Type: application/json", CR, LF
	db "Content-Length: 33", CR, LF
	db CR, LF
	db '{"error":"Redis publish failed"}'
payments_error_len: equ $ - payments_error_response

; Payments summary response (JSON)
payments_summary_response:
	db "HTTP/1.1 200 OK", CR, LF
	db "Content-Type: application/json", CR, LF
	db "Content-Length: 98", CR, LF
	db CR, LF
	db '{"default":{"totalRequests":0,"totalAmount":0.0},"fallback":{"totalRequests":0,"totalAmount":0.0}}'
payments_summary_len: equ $ - payments_summary_response

; Dynamic HTTP response headers
http_summary_header: db "HTTP/1.1 200 OK", CR, LF, "Content-Type: application/json", CR, LF, "Content-Length: "
http_summary_header_len: equ $ - http_summary_header

section .bss
json_response_len: resb 8       ; Length of dynamic JSON response
dynamic_http_buffer: resb 1024  ; Buffer for complete HTTP response

section .text
global route_request
global handle_post_payments
global handle_get_payments_summary
global send_payments_response
global send_summary_response
global build_dynamic_http_response

route_request:
	; Check if POST /payments
	call check_post_payments
	cmp rax, 1
	je .handle_post_payments
	
	; Check if GET /payments-summary
	call check_get_payments_summary
	cmp rax, 1
	je .handle_get_payments_summary
	
	; Default: return 0 (not handled)
	xor rax, rax
	ret
	
.handle_post_payments:
	call handle_post_payments
	ret
	
.handle_get_payments_summary:
	call handle_get_payments_summary
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

check_get_payments_summary:
	push rbx
	push rcx
	push rdi
	push rsi
	
	; Check verb == "GET"
	mov rdi, [verb_ptr]
	mov rsi, get_verb
	mov rcx, get_verb_len
	cmp rcx, [verb_len]
	jne .not_match_get
	repe cmpsb
	jne .not_match_get
	
	; Check path == "/payments-summary"
	mov rdi, [path_ptr]
	mov rsi, payments_summary_path
	mov rcx, payments_summary_path_len
	cmp rcx, [path_len]
	jne .not_match_get
	repe cmpsb
	jne .not_match_get
	
	; Match found
	mov rax, 1
	jmp .done_get
	
.not_match_get:
	xor rax, rax
	
.done_get:
	pop rsi
	pop rdi
	pop rcx
	pop rbx
	ret

handle_post_payments:
	; Publish JSON body to Redis payments channel
	mov rsi, [body_ptr]
	mov rdx, [body_len]
	call redis_publish_body
	
	; Set response handled flag (rax already contains Redis result)
	ret

handle_get_payments_summary:
	; Simple implementation - just use global counters
	call redis_query_summary
	cmp rax, 1
	jne .query_failed
	
	; Parse Redis responses
	call parse_redis_responses
	
	; Build dynamic JSON response
	call build_summary_json
	
	; Store JSON length in global variable for response function
	mov [json_response_len], rax
	
	; Redis query succeeded, return GET success code
	mov rax, 2  ; GET success flag
	ret

.query_failed:
	; Redis query failed, return error code
	mov rax, 0  ; Error flag
	ret

send_payments_response:
	; Check result code: 1=POST success, 2=GET success, other=error
	cmp rax, 1
	je .send_post_success
	cmp rax, 2
	je .send_get_success
	
	; Send error response
	mov rdi, r10
	mov rsi, payments_error_response
	mov rdx, payments_error_len
	mov rax, SYS_write
	syscall
	ret
	
.send_post_success:
	; Send POST /payments success response
	mov rdi, r10
	mov rsi, payments_success_response
	mov rdx, payments_success_len
	mov rax, SYS_write
	syscall
	ret
	
.send_get_success:
	; Build dynamic HTTP response with correct Content-Length
	call build_dynamic_http_response
	
	; Send dynamic response
	mov rdi, r10
	mov rsi, dynamic_http_buffer
	mov rdx, rax  ; Length returned by build function
	mov rax, SYS_write
	syscall
	ret

; Build complete HTTP response with dynamic JSON
; Returns: rax = total response length
build_dynamic_http_response:
	push rdi
	push rsi
	push rcx
	push rdx
	
	; Build HTTP response in dynamic_http_buffer
	mov rdi, dynamic_http_buffer
	
	; Copy HTTP headers: "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: "
	mov rsi, http_summary_header
	mov rcx, http_summary_header_len
	rep movsb
	
	; For now, use fixed Content-Length based on our JSON (simplified)
	; TODO: Convert [json_response_len] to string
	mov rax, [json_response_len]
	cmp rax, 100
	jl .under_100
	
	; Handle 3-digit numbers (100+)
	mov al, '1'
	stosb
	mov rax, [json_response_len]
	sub rax, 100
	jmp .add_tens
	
.under_100:
	mov rax, [json_response_len]
	
.add_tens:
	; Add tens digit
	mov bl, 10
	div bl
	add al, '0'
	stosb
	
	; Add ones digit  
	add ah, '0'
	mov al, ah
	stosb
	
	; Add final headers: "\r\n\r\n"
	mov al, CR
	stosb
	mov al, LF
	stosb
	mov al, CR
	stosb
	mov al, LF
	stosb
	
	; Copy JSON body
	mov rsi, summary_json_buffer
	mov rcx, [json_response_len]
	rep movsb
	
	; Calculate total response length
	mov rax, rdi
	sub rax, dynamic_http_buffer
	
	pop rdx
	pop rcx
	pop rsi
	pop rdi
	ret

