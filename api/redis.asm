%include "include/syscalls.inc"

; External functions
extern get_current_timestamp
extern timestamp_buffer

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

section .text
global redis_connect
global redis_publish_body
global redis_disconnect
global redis_query_summary
global redis_query_date_range
global redis_response_buffer
global parse_redis_responses
global build_summary_json
global summary_json_buffer
global convert_date_to_timestamp

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
	
	; Generate current timestamp
	call get_current_timestamp
	; rax now contains timestamp length (20)
	push rax                        ; save timestamp length
	
	; Calculate combined message length: body_len + 1 (semicolon) + timestamp_len
	mov rax, [rsp + 8]              ; get body length from stack
	add rax, 1                      ; add semicolon
	add rax, [rsp]                  ; add timestamp length
	push rax                        ; save combined length
	
	; Add "$<combined_len>\r\n"
	mov al, '$'
	stosb
	
	; Convert combined length to ASCII  
	mov rax, [rsp]                  ; get combined length from stack
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
	add rsp, 8                      ; remove string_len from stack
	add rsp, 8                      ; remove combined_len from stack
	add rsp, 8                      ; remove timestamp_len from stack
	pop rdx                         ; body length
	pop rsi                         ; body pointer
	push rsi
	push rdx
	mov rcx, rdx
	rep movsb
	
	; Add semicolon separator
	mov al, ';'
	stosb
	
	; Copy timestamp
	mov rsi, timestamp_buffer
	mov rcx, 20                     ; RFC3339 timestamp length
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

; Convert date string YYYY-MM-DD to Unix timestamp
; Input: rsi = pointer to date string (e.g., "2025-01-15")
; Output: rax = Unix timestamp
; Note: This is a simplified conversion that assumes UTC and doesn't handle leap years perfectly
convert_date_to_timestamp:
	push rbx
	push rcx
	push rdx
	push rdi
	
	; Parse year (4 digits)
	movzx rax, byte [rsi]
	sub rax, '0'
	imul rax, 1000
	movzx rbx, byte [rsi + 1]
	sub rbx, '0'
	imul rbx, 100
	add rax, rbx
	movzx rbx, byte [rsi + 2]
	sub rbx, '0'
	imul rbx, 10
	add rax, rbx
	movzx rbx, byte [rsi + 3]
	sub rbx, '0'
	add rax, rbx
	push rax                    ; Save year
	
	; Parse month (2 digits, skip '-')
	movzx rax, byte [rsi + 5]
	sub rax, '0'
	imul rax, 10
	movzx rbx, byte [rsi + 6]
	sub rbx, '0'
	add rax, rbx
	push rax                    ; Save month
	
	; Parse day (2 digits, skip '-')
	movzx rax, byte [rsi + 8]
	sub rax, '0'
	imul rax, 10
	movzx rbx, byte [rsi + 9]
	sub rbx, '0'
	add rax, rbx
	mov rbx, rax                ; rbx = day
	
	pop rcx                     ; rcx = month
	pop rax                     ; rax = year
	
	; Convert to Unix timestamp (simplified calculation)
	; Days since Unix epoch (1970-01-01)
	sub rax, 1970               ; Years since 1970
	imul rax, 365               ; Approximate days (ignoring leap years for simplicity)
	
	; Add days for months (simplified, not accounting for leap years)
	dec rcx                     ; Month is 1-based, make it 0-based
	cmp rcx, 0
	je .add_days
	imul rcx, 30                ; Approximate 30 days per month
	add rax, rcx
	
.add_days:
	add rax, rbx                ; Add day of month
	dec rax                     ; Day is 1-based, make it 0-based
	
	; Convert days to seconds
	imul rax, 86400             ; 24 * 60 * 60 seconds per day
	
	pop rdi
	pop rdx
	pop rcx
	pop rbx
	ret

; Query Redis sorted sets for date range
; Input: rsi = from_date_string, rdx = to_date_string
; Output: rax = 1 for success, 0 for failure
; Results stored in same buffers as redis_query_summary
redis_query_date_range:
	push rdi
	push rsi
	push rdx
	push rbx
	push rcx
	
	; Convert from_date to timestamp
	call convert_date_to_timestamp
	push rax                    ; Save from_timestamp
	
	; Convert to_date to timestamp (rdx already has to_date_string)
	mov rsi, rdx
	call convert_date_to_timestamp
	add rax, 86400              ; Add one day to make it inclusive
	mov rbx, rax                ; rbx = to_timestamp
	pop rax                     ; rax = from_timestamp
	
	; Connect to Redis
	call redis_connect
	cmp qword [redis_sockfd], -1
	je .date_query_failed
	
	; For now, fallback to global counters for date queries
	; TODO: Implement proper ZCOUNT and ZRANGEBYSCORE queries
	; This ensures we return actual payment data instead of 0
	
	; Query 1: GET totalRequests:default (fallback to global counters)
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
	
	call redis_disconnect
	mov rax, 1                  ; Success
	jmp .date_query_done
	
.date_query_failed:
	mov rax, 0                  ; Failure
	
.date_query_done:
	pop rcx
	pop rbx
	pop rdx
	pop rsi
	pop rdi
	ret

