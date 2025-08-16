%include "asm/include/syscalls.inc"

%define AF_INET 2
%define SOCK_STREAM 1
%define SOCK_PROTOCOL 0
%define CR 0xD
%define LF 0xA

section .data
; Redis server address (Docker service: redis at 172.20.0.2:6379)
redis_sockaddr:
	sa_family: dw AF_INET       ; 2 bytes
	port: dw 0xEB18             ; 2 bytes - 6379 in network byte order
	ip_addr: dd 0x020014AC      ; 4 bytes - 172.20.0.2 in network byte order
	sin_zero: dq 0              ; 8 bytes

; RESP protocol fragments for building dynamic messages
cmd_array: db "*3", CR, LF
cmd_publish: db "$7", CR, LF, "PUBLISH", CR, LF
cmd_channel: db "$8", CR, LF, "payments", CR, LF

; GET commands for summary queries
get_total_requests_default: db "*2", CR, LF, "$3", CR, LF, "GET", CR, LF, "$21", CR, LF, "totalRequests:default", CR, LF
get_total_requests_default_len: equ $ - get_total_requests_default

get_total_requests_fallback: db "*2", CR, LF, "$3", CR, LF, "GET", CR, LF, "$22", CR, LF, "totalRequests:fallback", CR, LF
get_total_requests_fallback_len: equ $ - get_total_requests_fallback

get_total_amount_default: db "*2", CR, LF, "$3", CR, LF, "GET", CR, LF, "$19", CR, LF, "totalAmount:default", CR, LF
get_total_amount_default_len: equ $ - get_total_amount_default

get_total_amount_fallback: db "*2", CR, LF, "$3", CR, LF, "GET", CR, LF, "$20", CR, LF, "totalAmount:fallback", CR, LF
get_total_amount_fallback_len: equ $ - get_total_amount_fallback

section .bss
redis_sockfd: resb 8            ; Redis socket file descriptor
dynamic_msg_buffer: resb 2048   ; Buffer for building dynamic RESP messages
length_str_buffer: resb 16      ; Buffer for converting length to string
redis_response_buffer: resb 4096 ; Buffer for Redis responses
total_requests_default: resb 8   ; Storage for default processor request count
total_requests_fallback: resb 8  ; Storage for fallback processor request count
total_amount_default: resb 8     ; Storage for default processor amount
total_amount_fallback: resb 8    ; Storage for fallback processor amount

section .text
global redis_connect
global redis_publish_body
global redis_disconnect
global redis_query_summary
global redis_response_buffer

redis_connect:
	; Create client socket
	mov rdi, AF_INET
	mov rsi, SOCK_STREAM
	mov rdx, SOCK_PROTOCOL
	mov rax, SYS_socket
	syscall
	
	; Check if socket creation failed
	cmp rax, 0
	jl .error
	mov [redis_sockfd], rax

	; Connect to Redis server
	mov rdi, [redis_sockfd]
	mov rsi, redis_sockaddr
	mov rdx, 16
	mov rax, SYS_connect
	syscall
	
	; Check if connection failed
	cmp rax, 0
	jl .error
	ret

.error:
	; Connection failed, close socket if it was created
	cmp qword [redis_sockfd], 0
	jle .skip_close
	mov rdi, [redis_sockfd]
	mov rax, SYS_close
	syscall
.skip_close:
	; Set socket to invalid value
	mov qword [redis_sockfd], -1
	ret

redis_disconnect:
	; Close Redis connection only if valid
	cmp qword [redis_sockfd], 0
	jle .skip_disconnect
	mov rdi, [redis_sockfd]
	mov rax, SYS_close
	syscall
.skip_disconnect:
	ret


; Convert number in rax to ASCII, store in length_str_buffer
; Returns: rax = string length
number_to_ascii:
	push rbx
	push rcx
	push rdx
	push rdi
	
	mov rbx, rax                    ; number to convert
	mov rdi, length_str_buffer + 15 ; work backwards
	mov byte [rdi], 0               ; null terminator
	dec rdi
	xor rcx, rcx                    ; digit count
	
.convert_loop:
	xor edx, edx                    ; clear EDX (32-bit clears upper 32 bits too)
	mov eax, ebx                    ; move lower 32 bits to EAX
	mov ebx, 10                     ; 32-bit divisor
	div ebx                         ; EAX = quotient, EDX = remainder
	add dl, '0'                     ; convert to ASCII
	mov [rdi], dl
	dec rdi
	inc rcx
	mov ebx, eax                    ; store quotient back in EBX
	cmp ebx, 0
	jne .convert_loop
	
	; Copy to start of buffer
	inc rdi                         ; point to first digit
	mov rsi, rdi
	push rcx                        ; save length
	mov rdi, length_str_buffer
	rep movsb                       ; copy rcx bytes
	
	pop rax                         ; return length
	
	pop rdi
	pop rdx
	pop rcx
	pop rbx
	ret

; Redis publish function - takes body_ptr in rsi, body_len in rdx
; Builds complete RESP message in memory first, then sends
; Returns: rax = 1 for success, 0 for failure
redis_publish_body:
	push rdi
	push rsi
	push rdx
	
	; Connect to Redis
	call redis_connect
	cmp qword [redis_sockfd], -1
	je .redis_failed
	
	; Build complete RESP message in dynamic_msg_buffer
	mov rdi, dynamic_msg_buffer
	
	; Copy "*3\r\n"
	mov rsi, cmd_array
	mov rcx, 4
	rep movsb
	
	; Copy "$7\r\nPUBLISH\r\n"
	mov rsi, cmd_publish
	mov rcx, 13
	rep movsb
	
	; Copy "$8\r\npayments\r\n"
	mov rsi, cmd_channel
	mov rcx, 14
	rep movsb
	
	; Add "$<body_len>\r\n"
	mov al, '$'
	stosb
	
	; Convert body length to ASCII  
	mov rax, [rsp]                  ; get body length from stack
	call number_to_ascii
	push rax                        ; save length string size
	
	; Copy length string
	mov rsi, length_str_buffer
	mov rcx, [rsp]                  ; use saved length string size from stack
	rep movsb
	
	; Add "\r\n"
	mov al, CR
	stosb
	mov al, LF
	stosb
	
	; Copy body content  
	add rsp, 8                      ; remove string_len from stack first
	pop rdx                         ; body length
	pop rsi                         ; body pointer
	push rsi
	push rdx
	mov rcx, rdx
	rep movsb
	
	; Add final "\r\n"
	mov al, CR
	stosb
	mov al, LF
	stosb
	
	; Calculate total message length
	mov rbx, rdi
	sub rbx, dynamic_msg_buffer
	
	; Send complete message with single write
	mov rdi, [redis_sockfd]
	mov rsi, dynamic_msg_buffer
	mov rdx, rbx
	mov rax, SYS_write
	syscall
	
	
	call redis_disconnect
	mov rax, 1       ; success
	jmp .done
	
.redis_failed:
	mov rax, 0       ; failure
	
.done:
	pop rdx
	pop rsi
	pop rdi
	ret

; Redis query summary function - queries all 4 counters
; Stores results in global variables for debugging
; Returns: rax = 1 for success, 0 for failure
redis_query_summary:
	push rdi
	push rsi
	push rdx
	
	; Connect to Redis
	call redis_connect
	cmp qword [redis_sockfd], -1
	je .query_failed
	
	; Query 1: GET totalRequests:default
	mov rdi, [redis_sockfd]
	mov rsi, get_total_requests_default
	mov rdx, get_total_requests_default_len
	mov rax, SYS_write
	syscall
	
	; Read response
	mov rdi, [redis_sockfd]
	mov rsi, redis_response_buffer
	mov rdx, 4096
	mov rax, SYS_read
	syscall
	
	; Store first response length in total_requests_default (for debugging)
	mov [total_requests_default], rax
	
	; Query 2: GET totalRequests:fallback
	mov rdi, [redis_sockfd]
	mov rsi, get_total_requests_fallback
	mov rdx, get_total_requests_fallback_len
	mov rax, SYS_write
	syscall
	
	; Read response
	mov rdi, [redis_sockfd]
	mov rsi, redis_response_buffer
	mov rdx, 4096
	mov rax, SYS_read
	syscall
	
	; Store second response length in total_requests_fallback (for debugging)
	mov [total_requests_fallback], rax
	
	; Disconnect
	call redis_disconnect
	mov rax, 1       ; success
	jmp .query_done
	
.query_failed:
	mov rax, 0       ; failure
	
.query_done:
	pop rdx
	pop rsi
	pop rdi
	ret

