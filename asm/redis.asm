%include "asm/include/syscalls.inc"

; External declarations for query parameters from http.asm
extern from_param_ptr
extern from_param_len
extern to_param_ptr
extern to_param_len

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

; ZRANGEBYSCORE command fragments
zrangebyscore_cmd_start: db "*4", CR, LF, "$13", CR, LF, "ZRANGEBYSCORE", CR, LF, "$12", CR, LF, "payments_log", CR, LF
zrangebyscore_cmd_start_len: equ $ - zrangebyscore_cmd_start

; Special score values for ZRANGEBYSCORE
neg_inf_score: db "-inf"
neg_inf_score_len: equ $ - neg_inf_score
pos_inf_score: db "+inf"
pos_inf_score_len: equ $ - pos_inf_score

; JSON parsing constants
processor_key: db '"processor":"'
processor_key_len: equ $ - processor_key
amount_key: db '"amount":'
amount_key_len: equ $ - amount_key
default_processor: db "default"
default_processor_len: equ $ - default_processor
fallback_processor: db "fallback"
fallback_processor_len: equ $ - fallback_processor

; JSON building fragments
json_start_default: db '{"default":{"totalRequests":'
json_start_default_len: equ $ - json_start_default

json_mid_amount: db ',"totalAmount":'
json_mid_amount_len: equ $ - json_mid_amount

json_mid_fallback: db '},"fallback":{"totalRequests":'
json_mid_fallback_len: equ $ - json_mid_fallback

json_end: db '}}'
json_end_len: equ $ - json_end

default_amount: db '0.0'
default_amount_len: equ $ - default_amount

section .bss
redis_sockfd: resb 8            ; Redis socket file descriptor
dynamic_msg_buffer: resb 2048   ; Buffer for building dynamic RESP messages
length_str_buffer: resb 16      ; Buffer for converting length to string
redis_response_buffer: resb 4096 ; Buffer for Redis responses
summary_json_buffer: resb 512   ; Buffer for dynamic JSON response
; Separate response buffers for each query
resp_buffer_1: resb 1024        ; Response buffer for totalRequests:default
resp_buffer_2: resb 1024        ; Response buffer for totalRequests:fallback
resp_buffer_3: resb 1024        ; Response buffer for totalAmount:default
resp_buffer_4: resb 1024        ; Response buffer for totalAmount:fallback
total_requests_default: resb 8   ; Storage for default processor request count
total_requests_fallback: resb 8  ; Storage for fallback processor request count
total_amount_default: resb 8     ; Storage for default processor amount
total_amount_fallback: resb 8    ; Storage for fallback processor amount
; Parsed values from Redis
req_default_val: resb 8         ; Parsed totalRequests:default
req_fallback_val: resb 8        ; Parsed totalRequests:fallback  
amt_default_val: resb 8         ; Parsed totalAmount:default (unused - use string version)
amt_fallback_val: resb 8        ; Parsed totalAmount:fallback (unused - use string version)
; String buffers for amount values
amt_default_str: resb 16        ; String representation of totalAmount:default  
amt_default_len: resb 8         ; Length of amt_default_str
amt_fallback_str: resb 16       ; String representation of totalAmount:fallback
amt_fallback_len: resb 8        ; Length of amt_fallback_str
; ZRANGEBYSCORE functionality
zrange_response_buffer: resb 8192 ; Large buffer for multiple JSON payment responses
filtered_json_buffer: resb 1024   ; Buffer for building filtered summary JSON
min_score_buffer: resb 32         ; Buffer for min score string
max_score_buffer: resb 32         ; Buffer for max score string
min_score_len: resb 8             ; Length of min score string
max_score_len: resb 8             ; Length of max score string
; Filtered summary counters
filtered_default_requests: resb 8  ; Default processor request count
filtered_default_amount: resb 8    ; Default processor amount (integer representation)
filtered_fallback_requests: resb 8 ; Fallback processor request count
filtered_fallback_amount: resb 8   ; Fallback processor amount (integer representation)

section .text
global redis_connect
global redis_publish_body
global redis_disconnect
global redis_query_summary
global redis_response_buffer
global parse_redis_responses
global build_summary_json
global summary_json_buffer
global redis_zrangebyscore
global rfc3339_to_unix_score
global parse_payment_json
global build_filtered_summary
global filtered_json_buffer

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
; Stores results in separate buffers for parsing
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
	
	; Read response into buffer 1
	mov rdi, [redis_sockfd]
	mov rsi, resp_buffer_1
	mov rdx, 1024
	mov rax, SYS_read
	syscall
	mov [total_requests_default], rax
	
	; Query 2: GET totalRequests:fallback
	mov rdi, [redis_sockfd]
	mov rsi, get_total_requests_fallback
	mov rdx, get_total_requests_fallback_len
	mov rax, SYS_write
	syscall
	
	; Read response into buffer 2
	mov rdi, [redis_sockfd]
	mov rsi, resp_buffer_2
	mov rdx, 1024
	mov rax, SYS_read
	syscall
	mov [total_requests_fallback], rax
	
	; Query 3: GET totalAmount:default
	mov rdi, [redis_sockfd]
	mov rsi, get_total_amount_default
	mov rdx, get_total_amount_default_len
	mov rax, SYS_write
	syscall
	
	; Read response into buffer 3
	mov rdi, [redis_sockfd]
	mov rsi, resp_buffer_3
	mov rdx, 1024
	mov rax, SYS_read
	syscall
	mov [total_amount_default], rax
	
	; Query 4: GET totalAmount:fallback
	mov rdi, [redis_sockfd]
	mov rsi, get_total_amount_fallback
	mov rdx, get_total_amount_fallback_len
	mov rax, SYS_write
	syscall
	
	; Read response into buffer 4
	mov rdi, [redis_sockfd]
	mov rsi, resp_buffer_4
	mov rdx, 1024
	mov rax, SYS_read
	syscall
	mov [total_amount_fallback], rax
	
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

; Parse Redis RESP responses and extract values
; Analyzes all 4 separate response buffers and extracts values
parse_redis_responses:
	push rdi
	push rsi
	push rcx
	push rdx
	
	; Parse first response: totalRequests:default from resp_buffer_1 (integer)
	mov rsi, resp_buffer_1
	call parse_single_resp_value
	mov [req_default_val], rax
	
	; Parse second response: totalRequests:fallback from resp_buffer_2 (integer)
	mov rsi, resp_buffer_2
	call parse_single_resp_value
	mov [req_fallback_val], rax
	
	; Parse third response: totalAmount:default from resp_buffer_3 (string)
	mov rsi, resp_buffer_3
	mov rdi, amt_default_str
	mov rdx, 16  ; Max buffer size
	call parse_resp_string
	mov [amt_default_len], rax
	
	; Parse fourth response: totalAmount:fallback from resp_buffer_4 (string)
	mov rsi, resp_buffer_4
	mov rdi, amt_fallback_str
	mov rdx, 16  ; Max buffer size
	call parse_resp_string
	mov [amt_fallback_len], rax
	
	pop rdx
	pop rcx
	pop rsi
	pop rdi
	ret

; Parse single RESP bulk string response
; Input: rsi = pointer to RESP response
; Output: rax = parsed integer value (0 if null/error)
parse_single_resp_value:
	push rdi
	push rcx
	push rdx
	push rbx
	
	; Check first character
	mov al, [rsi]
	cmp al, '$'
	jne .parse_error
	
	inc rsi  ; Skip '$'
	
	; Check if null response ($-1)
	mov al, [rsi]
	cmp al, '-'
	je .null_response
	
	; Parse length field until \r
	xor rcx, rcx  ; rcx = parsed length
.parse_length_loop:
	mov al, [rsi]
	cmp al, CR
	je .length_done
	cmp al, '0'
	jb .parse_error
	cmp al, '9'
	ja .parse_error
	
	; rcx = rcx * 10 + (al - '0')
	imul rcx, 10
	sub al, '0'
	movzx rdx, al
	add rcx, rdx
	inc rsi
	jmp .parse_length_loop
	
.length_done:
	; Skip \r\n
	inc rsi  ; Skip \r
	inc rsi  ; Skip \n
	
	; Parse the actual number (rcx bytes)
	xor rax, rax  ; Result accumulator
	xor rbx, rbx  ; Current position
	
.parse_number_loop:
	cmp rbx, rcx
	jge .parse_done
	
	mov dl, [rsi + rbx]
	cmp dl, '0'
	jb .check_decimal  ; Check for decimal point
	cmp dl, '9'
	ja .check_decimal  ; Check for decimal point
	
	; rax = rax * 10 + (dl - '0')
	imul rax, 10
	sub dl, '0'
	movzx rdx, dl
	add rax, rdx
	inc rbx
	jmp .parse_number_loop

.check_decimal:
	; Check if it's a decimal point - if so, stop parsing (treat as integer part)
	cmp dl, '.'
	je .parse_done
	; Otherwise, stop parsing at any non-digit
	jmp .parse_done
	
.null_response:
	xor rax, rax  ; Return 0 for null
	jmp .parse_done
	
.parse_error:
	xor rax, rax  ; Return 0 for error
	
.parse_done:
	pop rbx
	pop rdx
	pop rcx
	pop rdi
	ret

; Build JSON summary with parsed values
; Returns: rax = length of JSON string
build_summary_json:
	push rdi
	push rsi
	push rcx
	
	; Build JSON string in summary_json_buffer
	mov rdi, summary_json_buffer
	
	; Start JSON: {"default":{"totalRequests":
	mov rsi, json_start_default
	mov rcx, json_start_default_len
	rep movsb
	
	; Add default requests value from parsed data
	mov rax, [req_default_val]
	call convert_number_to_string
	
	; Continue: ,"totalAmount":
	mov rsi, json_mid_amount
	mov rcx, json_mid_amount_len
	rep movsb
	
	; Add default amount value from parsed string
	cmp qword [amt_default_len], 0
	jne .use_default_amount
	; If empty, use "0"
	mov al, '0'
	stosb
	jmp .continue_fallback
.use_default_amount:
	mov rsi, amt_default_str
	mov rcx, [amt_default_len]
	rep movsb
.continue_fallback:
	
	; Continue: },"fallback":{"totalRequests":
	mov rsi, json_mid_fallback
	mov rcx, json_mid_fallback_len
	rep movsb
	
	; Add fallback requests value from parsed data
	mov rax, [req_fallback_val]
	call convert_number_to_string
	
	; Continue: ,"totalAmount":
	mov rsi, json_mid_amount
	mov rcx, json_mid_amount_len
	rep movsb
	
	; Add fallback amount value from parsed string
	cmp qword [amt_fallback_len], 0
	jne .use_fallback_amount
	; If empty, use "0"
	mov al, '0'
	stosb
	jmp .end_json
.use_fallback_amount:
	mov rsi, amt_fallback_str
	mov rcx, [amt_fallback_len]
	rep movsb
.end_json:
	
	; End JSON: }}
	mov rsi, json_end
	mov rcx, json_end_len
	rep movsb
	
	; Calculate total length
	mov rax, rdi
	sub rax, summary_json_buffer
	
	pop rcx
	pop rsi
	pop rdi
	ret

; Parse RESP bulk string and extract string value
; Input: rsi = pointer to RESP response, rdi = destination buffer, rdx = max buffer size
; Output: rax = length of extracted string (0 if null/error)
parse_resp_string:
	push rdi
	push rsi
	push rcx
	push rbx
	
	; Save destination buffer
	mov rbx, rdi
	
	; Check first character
	mov al, [rsi]
	cmp al, '$'
	jne .string_parse_error
	
	inc rsi  ; Skip '$'
	
	; Check if null response ($-1)
	mov al, [rsi]
	cmp al, '-'
	je .string_null_response
	
	; Parse length field until \r
	xor rcx, rcx  ; rcx = parsed length
.string_parse_length_loop:
	mov al, [rsi]
	cmp al, CR
	je .string_length_done
	cmp al, '0'
	jb .string_parse_error
	cmp al, '9'
	ja .string_parse_error
	
	; rcx = rcx * 10 + (al - '0')
	imul rcx, 10
	sub al, '0'
	movzx r8, al
	add rcx, r8
	inc rsi
	jmp .string_parse_length_loop
	
.string_length_done:
	; Skip \r\n
	inc rsi  ; Skip \r
	inc rsi  ; Skip \n
	
	; Check if length exceeds buffer size
	cmp rcx, rdx
	jg .string_parse_error
	
	; Copy string data to destination buffer
	push rcx  ; Save length for return
	rep movsb  ; Copy rcx bytes from rsi to rdi
	
	; Null-terminate the string
	mov byte [rdi], 0
	
	pop rax  ; Return length
	jmp .string_parse_done
	
.string_null_response:
	xor rax, rax  ; Return 0 for null
	jmp .string_parse_done
	
.string_parse_error:
	xor rax, rax  ; Return 0 for error
	
.string_parse_done:
	pop rbx
	pop rcx
	pop rsi
	pop rdi
	ret

; Convert number to ASCII string and store in RDI
; Input: rax = number to convert, rdi = destination buffer pointer
; Output: rdi = updated to point after the number string
; Modifies: rax, rbx, rcx, rdx
convert_number_to_string:
	push rbx
	push rcx
	push rdx
	push rsi
	
	; Handle zero case
	cmp rax, 0
	jne .not_zero
	mov byte [rdi], '0'
	inc rdi
	jmp .convert_done
	
.not_zero:
	; Convert number to string (backwards)
	mov rsi, rdi  ; Save start position
	mov rbx, rax  ; Number to convert
	xor rcx, rcx  ; Digit count
	
.digit_loop:
	xor rdx, rdx
	mov rax, rbx
	mov rbx, 10
	div rbx  ; rax = quotient, rdx = remainder
	add dl, '0'  ; Convert remainder to ASCII
	mov [rdi], dl
	inc rdi
	inc rcx
	mov rbx, rax  ; Continue with quotient
	cmp rbx, 0
	jne .digit_loop
	
	; Reverse the string in place
	dec rdi  ; Point to last digit
	mov rbx, rsi  ; Point to first digit
	
.reverse_loop:
	cmp rbx, rdi
	jge .reverse_done
	
	; Swap bytes at rbx and rdi
	mov al, [rbx]
	mov dl, [rdi]
	mov [rbx], dl
	mov [rdi], al
	
	inc rbx
	dec rdi
	jmp .reverse_loop
	
.reverse_done:
	; Set rdi to point after the string
	add rsi, rcx
	mov rdi, rsi
	
.convert_done:
	pop rsi
	pop rdx
	pop rcx
	pop rbx
	ret

; Build and execute ZRANGEBYSCORE command with dynamic min/max scores
; Input: Uses from_param_ptr/len and to_param_ptr/len from http.asm
; Output: Stores response in zrange_response_buffer, returns rax = 1 for success, 0 for failure
redis_zrangebyscore:
	push rdi
	push rsi
	push rdx
	push rcx
	push rbx
	
	; Connect to Redis
	call redis_connect
	cmp qword [redis_sockfd], -1
	je .zrange_failed
	
	; Build ZRANGEBYSCORE command in dynamic_msg_buffer
	mov rdi, dynamic_msg_buffer
	
	; Copy command start: "*4\r\n$13\r\nZRANGEBYSCORE\r\n$12\r\npayments_log\r\n"
	mov rsi, zrangebyscore_cmd_start
	mov rcx, zrangebyscore_cmd_start_len
	rep movsb
	
	; Add min score
	call build_min_score
	mov al, '$'
	stosb
	mov rax, [min_score_len]
	call number_to_ascii
	mov rsi, length_str_buffer
	mov rcx, rax  ; length of length string
	rep movsb
	mov al, CR
	stosb
	mov al, LF
	stosb
	mov rsi, min_score_buffer
	mov rcx, [min_score_len]
	rep movsb
	mov al, CR
	stosb
	mov al, LF
	stosb
	
	; Add max score
	call build_max_score
	mov al, '$'
	stosb
	mov rax, [max_score_len]
	call number_to_ascii
	mov rsi, length_str_buffer
	mov rcx, rax  ; length of length string
	rep movsb
	mov al, CR
	stosb
	mov al, LF
	stosb
	mov rsi, max_score_buffer
	mov rcx, [max_score_len]
	rep movsb
	mov al, CR
	stosb
	mov al, LF
	stosb
	
	; Calculate total message length
	mov rbx, rdi
	sub rbx, dynamic_msg_buffer
	
	; Send ZRANGEBYSCORE command
	mov rdi, [redis_sockfd]
	mov rsi, dynamic_msg_buffer
	mov rdx, rbx
	mov rax, SYS_write
	syscall
	
	; Read response
	mov rdi, [redis_sockfd]
	mov rsi, zrange_response_buffer
	mov rdx, 8192
	mov rax, SYS_read
	syscall
	
	; Disconnect
	call redis_disconnect
	mov rax, 1       ; success
	jmp .zrange_done
	
.zrange_failed:
	mov rax, 0       ; failure
	
.zrange_done:
	pop rbx
	pop rcx
	pop rdx
	pop rsi
	pop rdi
	ret

; Build min score based on from parameter
; Output: Sets min_score_buffer and min_score_len
build_min_score:
	push rdi
	push rsi
	push rcx
	
	; Check if from parameter exists
	cmp qword [from_param_len], 0
	je .use_neg_inf
	
	; Convert from parameter to Unix timestamp
	mov rsi, [from_param_ptr]
	mov rcx, [from_param_len]
	mov rdi, min_score_buffer
	call rfc3339_to_unix_score
	mov [min_score_len], rax
	jmp .min_score_done
	
.use_neg_inf:
	; Copy "-inf"
	mov rdi, min_score_buffer
	mov rsi, neg_inf_score
	mov rcx, neg_inf_score_len
	rep movsb
	mov qword [min_score_len], neg_inf_score_len
	
.min_score_done:
	pop rcx
	pop rsi
	pop rdi
	ret

; Build max score based on to parameter
; Output: Sets max_score_buffer and max_score_len
build_max_score:
	push rdi
	push rsi
	push rcx
	
	; Check if to parameter exists
	cmp qword [to_param_len], 0
	je .use_pos_inf
	
	; Convert to parameter to Unix timestamp
	mov rsi, [to_param_ptr]
	mov rcx, [to_param_len]
	mov rdi, max_score_buffer
	call rfc3339_to_unix_score
	mov [max_score_len], rax
	jmp .max_score_done
	
.use_pos_inf:
	; Copy "+inf"
	mov rdi, max_score_buffer
	mov rsi, pos_inf_score
	mov rcx, pos_inf_score_len
	rep movsb
	mov qword [max_score_len], pos_inf_score_len
	
.max_score_done:
	pop rcx
	pop rsi
	pop rdi
	ret

; Convert RFC3339 timestamp to Unix score string (simplified version)
; Input: rsi = RFC3339 string pointer, rcx = string length, rdi = output buffer
; Output: rax = length of score string
; Note: This is a simplified implementation for basic dates
rfc3339_to_unix_score:
	push rbx
	push rdx
	push rcx
	
	; For now, implement a simplified converter that extracts year and converts to approximate timestamp
	; Format expected: YYYY-MM-DDTHH:MM:SSZ
	; For simplicity, let's just use a basic approximation
	
	; Check if string is long enough for basic format
	cmp rcx, 19  ; "YYYY-MM-DDTHH:MM:SS" is 19 chars minimum
	jl .rfc_error
	
	; Extract year (first 4 characters) - avoid high byte registers
	; Parse year digit by digit into rbx
	xor rbx, rbx  ; Clear year accumulator
	
	; First digit
	mov al, [rsi]
	sub al, '0'
	movzx rax, al
	imul rbx, 10
	add rbx, rax
	
	; Second digit  
	mov al, [rsi + 1]
	sub al, '0'
	movzx rax, al
	imul rbx, 10
	add rbx, rax
	
	; Third digit
	mov al, [rsi + 2]
	sub al, '0'
	movzx rax, al
	imul rbx, 10
	add rbx, rax
	
	; Fourth digit
	mov al, [rsi + 3]
	sub al, '0'
	movzx rax, al
	imul rbx, 10
	add rbx, rax
	
	; Convert year to approximate Unix timestamp
	; (year - 1970) * 365 * 24 * 3600 (approximate)
	mov rax, rbx
	sub rax, 1970
	mov rbx, 31536000  ; seconds per year (365 * 24 * 3600)
	mul rbx
	
	; Convert result to string
	mov rbx, rax  ; Save timestamp value
	
	; Simple number to string conversion
	mov rcx, 0  ; digit counter
	push rdi    ; save output buffer start
	
.convert_timestamp:
	xor rdx, rdx
	mov rax, rbx
	mov rbx, 10
	div rbx
	add dl, '0'
	dec rdi
	mov [rdi], dl
	inc rcx
	mov rbx, rax
	cmp rbx, 0
	jne .convert_timestamp
	
	; Move string to start of buffer
	pop rbx  ; original buffer start
	push rcx ; save length
	mov rsi, rdi
	mov rdi, rbx
	rep movsb
	
	pop rax  ; return length
	jmp .rfc_done
	
.rfc_error:
	; Return "0" for invalid input
	mov byte [rdi], '0'
	mov rax, 1
	
.rfc_done:
	pop rcx
	pop rdx
	pop rbx
	ret

; Parse payment JSON to extract processor and amount
; Input: rsi = JSON string pointer, rcx = JSON string length
; Output: rax = processor type (0=default, 1=fallback, 2=unknown), rbx = amount as integer
parse_payment_json:
	push rdi
	push rdx
	push rcx
	push rsi
	
	; Initialize defaults
	mov rax, 2  ; unknown processor
	mov rbx, 0  ; zero amount
	
	; Search for processor field: "processor":"
	mov rdi, rsi  ; start of JSON
	mov rdx, rcx  ; JSON length
	
.find_processor:
	; Check if we have enough space for processor key
	cmp rdx, processor_key_len
	jl .parse_json_done
	
	; Compare with processor key
	push rsi
	push rcx
	push rdi
	mov rsi, processor_key
	mov rcx, processor_key_len
	repe cmpsb
	pop rdi
	pop rcx
	pop rsi
	je .found_processor_key
	
	; Move to next character
	inc rdi
	dec rdx
	jmp .find_processor
	
.found_processor_key:
	; Skip the processor key
	add rdi, processor_key_len
	sub rdx, processor_key_len
	
	; Check if it's "default" or "fallback"
	cmp rdx, default_processor_len
	jl .check_fallback
	
	push rsi
	push rcx
	mov rsi, default_processor
	mov rcx, default_processor_len
	repe cmpsb
	pop rcx
	pop rsi
	je .found_default
	
.check_fallback:
	cmp rdx, fallback_processor_len
	jl .find_amount
	
	mov rdi, rdi  ; reset position after processor key
	push rsi
	push rcx
	mov rsi, fallback_processor
	mov rcx, fallback_processor_len
	repe cmpsb
	pop rcx
	pop rsi
	je .found_fallback
	
	jmp .find_amount
	
.found_default:
	mov rax, 0  ; default processor
	jmp .find_amount
	
.found_fallback:
	mov rax, 1  ; fallback processor
	
.find_amount:
	; Search for amount field: "amount":
	mov rdi, rsi  ; reset to start of JSON
	mov rdx, rcx  ; reset to full length
	
.find_amount_loop:
	cmp rdx, amount_key_len
	jl .parse_json_done
	
	push rsi
	push rcx
	push rdi
	mov rsi, amount_key
	mov rcx, amount_key_len
	repe cmpsb
	pop rdi
	pop rcx
	pop rsi
	je .found_amount_key
	
	inc rdi
	dec rdx
	jmp .find_amount_loop
	
.found_amount_key:
	; Skip the amount key
	add rdi, amount_key_len
	sub rdx, amount_key_len
	
	; Parse the number (simplified - integer part only)
	xor rbx, rbx  ; amount accumulator
	
.parse_amount_digits:
	cmp rdx, 0
	je .parse_json_done
	
	mov al, [rdi]
	cmp al, '0'
	jb .parse_json_done  ; non-digit
	cmp al, '9'
	ja .check_decimal
	
	; Accumulate digit
	imul rbx, 10
	sub al, '0'
	movzx r8, al
	add rbx, r8
	
	inc rdi
	dec rdx
	jmp .parse_amount_digits
	
.check_decimal:
	; If it's a decimal point, we'll just use the integer part
	cmp al, '.'
	je .parse_json_done
	; Otherwise, we're done parsing
	
.parse_json_done:
	pop rsi
	pop rcx
	pop rdx
	pop rdi
	ret

; Build filtered summary JSON from ZRANGEBYSCORE response
; Input: zrange_response_buffer contains RESP array response
; Output: Sets filtered_json_buffer with JSON response, rax = JSON length
build_filtered_summary:
	push rbx
	push rcx
	push rdx
	push rdi
	push rsi
	
	; Initialize counters
	mov qword [filtered_default_requests], 0
	mov qword [filtered_default_amount], 0
	mov qword [filtered_fallback_requests], 0
	mov qword [filtered_fallback_amount], 0
	
	; Parse RESP array response from zrange_response_buffer
	mov rsi, zrange_response_buffer
	
	; Check if it's an array response (starts with '*')
	mov al, [rsi]
	cmp al, '*'
	jne .build_filtered_json  ; If not array, use zero counters
	
	inc rsi  ; Skip '*'
	
	; Parse array count (simplified - single digit for now)
	mov al, [rsi]
	cmp al, '0'
	jl .build_filtered_json
	cmp al, '9'
	ja .build_filtered_json
	sub al, '0'
	movzx rcx, al  ; Array count
	inc rsi  ; Skip count digit
	
	; Skip \r\n
	inc rsi
	inc rsi
	
.process_payment_loop:
	cmp rcx, 0
	je .build_filtered_json
	
	; Parse bulk string: $<len>\r\n<data>\r\n
	mov al, [rsi]
	cmp al, '$'
	jne .skip_payment
	inc rsi  ; Skip '$'
	
	; Parse length (simplified - assume single digit)
	mov al, [rsi]
	cmp al, '0'
	jl .skip_payment
	cmp al, '9'
	ja .skip_payment
	sub al, '0'
	movzx rdx, al  ; Bulk string length
	inc rsi  ; Skip length digit
	
	; Skip \r\n
	inc rsi
	inc rsi
	
	; Parse JSON payment data
	push rcx
	push rsi
	push rdx
	mov rcx, rdx  ; JSON length
	call parse_payment_json
	; rax = processor type, rbx = amount
	
	; Update counters based on processor type
	cmp rax, 0  ; default processor
	je .update_default
	cmp rax, 1  ; fallback processor
	je .update_fallback
	jmp .next_payment
	
.update_default:
	inc qword [filtered_default_requests]
	add qword [filtered_default_amount], rbx
	jmp .next_payment
	
.update_fallback:
	inc qword [filtered_fallback_requests]
	add qword [filtered_fallback_amount], rbx
	
.next_payment:
	pop rdx
	pop rsi
	pop rcx
	
	; Skip to next bulk string (skip data + \r\n)
	add rsi, rdx
	inc rsi  ; Skip \r
	inc rsi  ; Skip \n
	
	dec rcx
	jmp .process_payment_loop
	
.skip_payment:
	dec rcx
	jmp .process_payment_loop
	
.build_filtered_json:
	; Build JSON response in filtered_json_buffer
	mov rdi, filtered_json_buffer
	
	; Start JSON: {"default":{"totalRequests":
	mov rsi, json_start_default
	mov rcx, json_start_default_len
	rep movsb
	
	; Add default requests count
	mov rax, [filtered_default_requests]
	call convert_number_to_string
	
	; Continue: ,"totalAmount":
	mov rsi, json_mid_amount
	mov rcx, json_mid_amount_len
	rep movsb
	
	; Add default amount
	mov rax, [filtered_default_amount]
	call convert_number_to_string
	
	; Continue: },"fallback":{"totalRequests":
	mov rsi, json_mid_fallback
	mov rcx, json_mid_fallback_len
	rep movsb
	
	; Add fallback requests count
	mov rax, [filtered_fallback_requests]
	call convert_number_to_string
	
	; Continue: ,"totalAmount":
	mov rsi, json_mid_amount
	mov rcx, json_mid_amount_len
	rep movsb
	
	; Add fallback amount
	mov rax, [filtered_fallback_amount]
	call convert_number_to_string
	
	; End JSON: }}
	mov rsi, json_end
	mov rcx, json_end_len
	rep movsb
	
	; Calculate total length
	mov rax, rdi
	sub rax, filtered_json_buffer
	
	pop rsi
	pop rdi
	pop rdx
	pop rcx
	pop rbx
	ret

