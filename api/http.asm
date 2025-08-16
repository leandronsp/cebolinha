%include "include/syscalls.inc"

%define CR 0xD
%define LF 0xA

section .bss
request_buffer: resb 1024    ; Buffer to store incoming request
verb_ptr: resq 1              ; Pointer to verb start
verb_len: resq 1              ; Length of verb
path_ptr: resq 1              ; Pointer to path start
path_len: resq 1              ; Length of path
content_length_value: resq 1  ; Store the actual content length number
headers_start_ptr: resq 1     ; Pointer to start of headers (after headline CRLF)
body_ptr: resq 1              ; Pointer to body start
body_len: resq 1              ; Length of body (copy of content_length_value)
; Query parameter parsing
query_ptr: resq 1             ; Pointer to query string start (after '?')
query_len: resq 1             ; Length of query string
from_param_ptr: resq 1        ; Pointer to 'from' parameter value
from_param_len: resq 1        ; Length of 'from' parameter value
to_param_ptr: resq 1          ; Pointer to 'to' parameter value
to_param_len: resq 1          ; Length of 'to' parameter value

section .data
debug_verb_msg: db "Verb: "
debug_verb_msg_len: equ $ - debug_verb_msg
debug_path_msg: db "Path: "
debug_path_msg_len: equ $ - debug_path_msg
newline: db 10
content_length_header: db "Content-Length:"
content_length_header_len: equ $ - content_length_header
; Query parameter names
from_param_name: db "from="
from_param_name_len: equ $ - from_param_name
to_param_name: db "to="
to_param_name_len: equ $ - to_param_name
; 404 Not Found response
not_found_response:
	db "HTTP/1.1 404 Not Found", CR, LF
	db "Content-Type: application/json", CR, LF
	db "Content-Length: 22", CR, LF
	db CR, LF
	db '{"error":"Not Found"}'
not_found_response_len: equ $ - not_found_response

section .text
global send_not_found_response
global close_connection
global read_request
global parse_request
global print_request_info
global parse_headers
global verb_ptr
global verb_len
global path_ptr
global path_len
global body_ptr
global body_len
global query_ptr
global query_len
global from_param_ptr
global from_param_len
global to_param_ptr
global to_param_len
global parse_query_params

send_not_found_response:
	; fd is in r10
	mov rdi, r10
	mov rsi, not_found_response
	mov rdx, not_found_response_len
	mov rax, SYS_write
	syscall
	ret

close_connection:
	; fd is in r10
	mov rdi, r10
	mov rax, SYS_close
	syscall
	ret

read_request:
	; fd is in r10
	push r10
	mov rdi, r10                  ; fd
	mov rsi, request_buffer       ; buffer
	mov rdx, 1024                 ; max bytes to read
	mov rax, SYS_read
	syscall
	pop r10
	ret

parse_request:
	; Parse the HTTP request headline
	; Format: VERB PATH HTTP/1.1\r\n
	push rbx
	push rcx

	; Set verb_ptr to start of buffer
	mov rax, request_buffer
	mov [verb_ptr], rax

	; Find first space (end of verb)
	mov rsi, request_buffer
	xor rcx, rcx
.find_verb_end:
	mov al, [rsi]
	cmp al, ' '
	je .found_verb_end
	inc rsi
	inc rcx
	jmp .find_verb_end

.found_verb_end:
	; Store verb length
	mov [verb_len], rcx

	; Skip the space, set path_ptr
	inc rsi
	mov [path_ptr], rsi

	; Find second space, CR, or '?' (end of path/start of query)
	xor rcx, rcx
	mov qword [query_ptr], 0  ; Initialize query_ptr to null
	mov qword [query_len], 0  ; Initialize query_len to 0
.find_path_end:
	mov al, [rsi]
	cmp al, ' '
	je .found_path_end
	cmp al, CR
	je .found_path_end
	cmp al, '?'
	je .found_query_start
	inc rsi
	inc rcx
	jmp .find_path_end

.found_query_start:
	; Store path length (excluding '?')
	mov [path_len], rcx
	
	; Save query start position (skip '?')
	inc rsi
	mov [query_ptr], rsi
	
	; Find end of query string (space or CR)
	xor rcx, rcx
.find_query_end:
	mov al, [rsi]
	cmp al, ' '
	je .found_query_end
	cmp al, CR
	je .found_query_end
	inc rsi
	inc rcx
	jmp .find_query_end
	
.found_query_end:
	; Store query length
	mov [query_len], rcx
	; rsi is now at space or CR after query - this is correct position
	jmp .skip_to_headers

.found_path_end:
	; Store path length (no query string found)
	mov [path_len], rcx
	; rsi is now at space or CR after path - this is correct position

	; Skip to end of headline (find LF after CR)
.skip_to_headers:
	mov al, [rsi]
	cmp al, LF
	je .found_headline_end
	inc rsi
	jmp .skip_to_headers

.found_headline_end:
	inc rsi                    ; Skip the LF
	mov [headers_start_ptr], rsi  ; Save headers start position

	pop rcx
	pop rbx
	ret

parse_headers:
	push rbx
	push rcx
	push rdx
	push rdi
	push rsi
	
	mov rbx, [headers_start_ptr]
	mov qword [content_length_value], 0  ; Initialize to 0
	
.next_header:
	; Check if we hit empty line (CRLF CRLF = end of headers)
	mov al, [rbx]
	cmp al, CR
	jne .check_content_length
	mov al, [rbx + 1]
	cmp al, LF
	jne .check_content_length
	
	; Found end of headers
	jmp .headers_done
	
.check_content_length:
	; Use repe cmpsb to compare "Content-Length:"
	mov rdi, rbx                        ; current header line
	mov rsi, content_length_header      ; target string
	mov rcx, content_length_header_len  ; string length
	repe cmpsb
	je .found_content_length           ; strings match
	
.skip_line:
	; Skip to next line
	mov al, [rbx]
	cmp al, LF
	je .next_line
	inc rbx
	jmp .skip_line
	
.next_line:
	inc rbx                 ; Skip LF
	jmp .next_header
	
.found_content_length:
	; rbx points after "Content-Length:"
	mov rbx, rdi            ; rdi was advanced by repe cmpsb
	
	; Skip spaces
.skip_spaces:
	mov al, [rbx]
	cmp al, ' '
	jne .parse_number
	inc rbx
	jmp .skip_spaces
	
.parse_number:
	xor rax, rax            ; Clear accumulator
	xor rcx, rcx            ; Clear temp
	
.digit_loop:
	mov cl, [rbx]
	cmp cl, '0'
	jl .number_done
	cmp cl, '9'
	jg .number_done
	
	sub cl, '0'            ; Convert ASCII to number
	imul rax, 10           ; Multiply current by 10
	add rax, rcx           ; Add new digit
	inc rbx
	jmp .digit_loop
	
.number_done:
	mov [content_length_value], rax
	jmp .skip_line         ; Continue parsing other headers
	
.headers_done:
debug:
	; rbx points to CR of empty line (CRLF CRLF)
	; Body starts after the CRLF
	add rbx, 2              ; Skip CRLF
	mov [body_ptr], rbx     ; Save body start pointer
	mov rax, [content_length_value]
	mov [body_len], rax     ; Save body length
	
	pop rsi
	pop rdi
	pop rdx
	pop rcx
	pop rbx
	ret

print_request_info:
	push r10

	; Print "Verb: "
	mov rdi, 1                    ; stdout
	mov rsi, debug_verb_msg
	mov rdx, debug_verb_msg_len
	mov rax, SYS_write
	syscall

	; Print the verb
	mov rdi, 1                    ; stdout
	mov rsi, [verb_ptr]
	mov rdx, [verb_len]
	mov rax, SYS_write
	syscall

	; Print newline
	mov rdi, 1                    ; stdout
	mov rsi, newline
	mov rdx, 1
	mov rax, SYS_write
	syscall

	; Print "Path: "
	mov rdi, 1                    ; stdout
	mov rsi, debug_path_msg
	mov rdx, debug_path_msg_len
	mov rax, SYS_write
	syscall

	; Print the path
	mov rdi, 1                    ; stdout
	mov rsi, [path_ptr]
	mov rdx, [path_len]
	mov rax, SYS_write
	syscall

	; Print newline
	mov rdi, 1                    ; stdout
	mov rsi, newline
	mov rdx, 1
	mov rax, SYS_write
	syscall

	pop r10
	ret

; Parse query parameters from query string
; Extracts 'from' and 'to' parameters if they exist
; Input: query_ptr and query_len must be set
; Output: Sets from_param_ptr/len and to_param_ptr/len
parse_query_params:
	push rbx
	push rcx
	push rdx
	push rdi
	push rsi
	
	; Initialize parameter pointers to null
	mov qword [from_param_ptr], 0
	mov qword [from_param_len], 0
	mov qword [to_param_ptr], 0
	mov qword [to_param_len], 0
	
	; Check if we have a query string
	cmp qword [query_len], 0
	je .no_query_string
	
	; Start parsing from beginning of query string
	mov rsi, [query_ptr]
	mov rbx, [query_len]
	
.parse_param_loop:
	; Check if we've reached the end
	cmp rbx, 0
	je .done_parsing
	
	; Check for 'from=' parameter
	cmp rbx, from_param_name_len
	jl .check_to_param
	
	mov rdi, rsi
	mov rcx, from_param_name_len
	push rsi
	push rbx
	mov rsi, from_param_name
	repe cmpsb
	pop rbx
	pop rsi
	je .found_from_param
	
.check_to_param:
	; Check for 'to=' parameter
	cmp rbx, to_param_name_len
	jl .skip_to_next
	
	mov rdi, rsi
	mov rcx, to_param_name_len
	push rsi
	push rbx
	mov rsi, to_param_name
	repe cmpsb
	pop rbx
	pop rsi
	je .found_to_param
	
.skip_to_next:
	; Skip to next character
	inc rsi
	dec rbx
	jmp .parse_param_loop
	
.found_from_param:
	; Skip 'from=' part
	add rsi, from_param_name_len
	sub rbx, from_param_name_len
	
	; Save start of value
	mov [from_param_ptr], rsi
	
	; Find end of value (& or end of string)
	xor rcx, rcx
.find_from_end:
	cmp rbx, 0
	je .found_from_end
	mov al, [rsi]
	cmp al, '&'
	je .found_from_end
	inc rsi
	inc rcx
	dec rbx
	jmp .find_from_end
	
.found_from_end:
	mov [from_param_len], rcx
	
	; Skip '&' if present
	cmp rbx, 0
	je .parse_param_loop
	inc rsi
	dec rbx
	jmp .parse_param_loop
	
.found_to_param:
	; Skip 'to=' part
	add rsi, to_param_name_len
	sub rbx, to_param_name_len
	
	; Save start of value
	mov [to_param_ptr], rsi
	
	; Find end of value (& or end of string)
	xor rcx, rcx
.find_to_end:
	cmp rbx, 0
	je .found_to_end
	mov al, [rsi]
	cmp al, '&'
	je .found_to_end
	inc rsi
	inc rcx
	dec rbx
	jmp .find_to_end
	
.found_to_end:
	mov [to_param_len], rcx
	
	; Skip '&' if present
	cmp rbx, 0
	je .parse_param_loop
	inc rsi
	dec rbx
	jmp .parse_param_loop
	
.no_query_string:
.done_parsing:
	pop rsi
	pop rdi
	pop rdx
	pop rcx
	pop rbx
	ret
