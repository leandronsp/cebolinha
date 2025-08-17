; syscalls.inc - Linux x86-64 system call numbers
; Used by all modules in the Dinossauro HTTP server

; I/O system calls
%define SYS_read 0
%define SYS_write 1
%define SYS_close 3

; Network system calls
%define SYS_socket 41
%define SYS_connect 42
%define SYS_bind 49
%define SYS_listen 50
%define SYS_setsockopt 54

; Process control
%define SYS_exit 60

; Time system calls
%define SYS_clock_gettime 228

; Network system calls (extended)
%define SYS_accept4 288
