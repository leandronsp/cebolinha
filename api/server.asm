global _start
extern sockfd
extern create_socket
extern bind_socket
extern listen_socket
extern accept_connection
extern send_not_found_response
extern close_connection
extern read_request
extern parse_request
extern parse_headers
extern parse_query_params
extern print_request_info
extern route_request
extern send_payments_response

%include "include/syscalls.inc"

section .text
_start:
.socket:
	call create_socket
	call bind_socket
	call listen_socket

.accept:
	call accept_connection
	mov r10, rax
	call action
	jmp .accept

action:
	call read_request       ; Read HTTP request
	call parse_request      ; Parse verb and path
	call parse_query_params ; Parse query parameters (from/to)
	call parse_headers      ; Parse headers and body
	call print_request_info ; Print to stdout
	
	; Check for specific routes
	call route_request
	cmp rax, 0
	je .default_route
	
	; Specific route handled - rax contains Redis result (1=success, 2=error)
	call send_payments_response
	jmp .close
	
.default_route:
	; Default route - unhandled (404 Not Found)
	call send_not_found_response ; Send 404 response
	
.close:
	call close_connection   ; Close socket
	ret
