%include "include/syscalls.inc"

%define CLOCK_REALTIME 0

section .data
; Time structure for clock_gettime
timespec:
    tv_sec: dq 0    ; seconds since epoch
    tv_nsec: dq 0   ; nanoseconds

; RFC3339 timestamp buffer: 2006-01-02T15:04:05Z (20 chars + null)
timestamp_buffer: times 21 db 0

; Days in each month (non-leap year)
month_days: db 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

; Month lengths for leap year
month_days_leap: db 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31

section .text
global get_current_timestamp
global timestamp_buffer

; Get current timestamp in RFC3339 format
; Returns: timestamp_buffer contains the formatted timestamp
; Returns: rax = length of timestamp (20)
get_current_timestamp:
    push rdi
    push rsi
    push rdx
    push rcx
    push r8
    push r9
    push r10
    push r11
    
    ; Get current time
    mov rdi, CLOCK_REALTIME
    mov rsi, timespec
    mov rax, SYS_clock_gettime
    syscall
    
    ; Convert seconds since epoch to date/time
    mov rax, [tv_sec]
    
    ; Calculate year, month, day, hour, minute, second
    call epoch_to_datetime
    
    ; Format as RFC3339: YYYY-MM-DDTHH:MM:SSZ
    call format_rfc3339
    
    pop r11
    pop r10
    pop r9
    pop r8
    pop rcx
    pop rdx
    pop rsi
    pop rdi
    
    mov rax, 20  ; RFC3339 timestamp length
    ret

; Convert epoch seconds to date/time components
; Input: rax = seconds since epoch
; Outputs: year in r8, month in r9, day in r10, hour in r11, minute in rcx, second in rdx
epoch_to_datetime:
    push rax
    
    ; Calculate seconds, minutes, hours
    xor rdx, rdx
    mov rbx, 60
    div rbx
    mov rdx, rdx  ; seconds (0-59)
    push rdx
    
    xor rdx, rdx
    div rbx
    mov rcx, rdx  ; minutes (0-59)
    push rcx
    
    xor rdx, rdx
    mov rbx, 24
    div rbx
    mov r11, rdx  ; hours (0-23)
    push r11
    
    ; rax now contains days since epoch (1970-01-01)
    mov r8, 1970  ; start year
    
.year_loop:
    ; Check if leap year
    mov rbx, r8
    call is_leap_year
    cmp rax, 1
    je .leap_year
    
    ; Regular year (365 days)
    cmp rax, 365
    jl .found_year
    sub rax, 365
    inc r8
    jmp .year_loop
    
.leap_year:
    ; Leap year (366 days)
    cmp rax, 366
    jl .found_year
    sub rax, 366
    inc r8
    jmp .year_loop
    
.found_year:
    ; rax now contains days within the year (0-based)
    ; r8 contains the year
    
    ; Find month and day
    mov r9, 1  ; month (1-12)
    mov rbx, r8
    call is_leap_year
    cmp rax, 1
    je .use_leap_days
    
    mov rsi, month_days
    jmp .month_loop
    
.use_leap_days:
    mov rsi, month_days_leap
    
.month_loop:
    movzx rbx, byte [rsi + r9 - 1]  ; days in current month
    cmp rax, rbx
    jl .found_month
    sub rax, rbx
    inc r9
    jmp .month_loop
    
.found_month:
    inc rax  ; day is 1-based
    mov r10, rax  ; day (1-31)
    
    ; Restore hour, minute, second from stack
    pop r11  ; hours
    pop rcx  ; minutes  
    pop rdx  ; seconds
    pop rax  ; original epoch (not needed)
    
    ret

; Check if year is leap year
; Input: rbx = year
; Output: rax = 1 if leap year, 0 otherwise
is_leap_year:
    ; Leap year if divisible by 4 AND (not divisible by 100 OR divisible by 400)
    mov rax, rbx
    xor rdx, rdx
    mov rcx, 4
    div rcx
    test rdx, rdx
    jnz .not_leap  ; not divisible by 4
    
    mov rax, rbx
    xor rdx, rdx
    mov rcx, 100
    div rcx
    test rdx, rdx
    jnz .is_leap  ; divisible by 4, not by 100
    
    mov rax, rbx
    xor rdx, rdx
    mov rcx, 400
    div rcx
    test rdx, rdx
    jz .is_leap  ; divisible by 400
    
.not_leap:
    xor rax, rax
    ret
    
.is_leap:
    mov rax, 1
    ret

; Format date/time as RFC3339
; Inputs: r8=year, r9=month, r10=day, r11=hour, rcx=minute, rdx=second
format_rfc3339:
    push rdi
    push rsi
    push rax
    
    mov rdi, timestamp_buffer
    
    ; Format year (4 digits)
    mov rax, r8
    call format_4_digits
    
    ; Add dash
    mov al, '-'
    stosb
    
    ; Format month (2 digits)
    mov rax, r9
    call format_2_digits
    
    ; Add dash
    mov al, '-'
    stosb
    
    ; Format day (2 digits)
    mov rax, r10
    call format_2_digits
    
    ; Add T
    mov al, 'T'
    stosb
    
    ; Format hour (2 digits)
    mov rax, r11
    call format_2_digits
    
    ; Add colon
    mov al, ':'
    stosb
    
    ; Format minute (2 digits)
    mov rax, rcx
    call format_2_digits
    
    ; Add colon
    mov al, ':'
    stosb
    
    ; Format second (2 digits)
    mov rax, rdx
    call format_2_digits
    
    ; Add Z
    mov al, 'Z'
    stosb
    
    ; Null terminate
    mov al, 0
    stosb
    
    pop rax
    pop rsi
    pop rdi
    ret

; Format number as 4 digits
; Input: rax = number, rdi = buffer pointer (updated)
format_4_digits:
    push rax
    push rbx
    push rdx
    
    ; Extract thousands
    xor rdx, rdx
    mov rbx, 1000
    div rbx
    add al, '0'
    stosb
    mov rax, rdx
    
    ; Extract hundreds  
    xor rdx, rdx
    mov rbx, 100
    div rbx
    add al, '0'
    stosb
    mov rax, rdx
    
    ; Extract tens
    xor rdx, rdx
    mov rbx, 10
    div rbx
    add al, '0'
    stosb
    
    ; Units
    add dl, '0'
    mov al, dl
    stosb
    
    pop rdx
    pop rbx
    pop rax
    ret

; Format number as 2 digits
; Input: rax = number, rdi = buffer pointer (updated)
format_2_digits:
    push rax
    push rbx
    push rdx
    
    ; Extract tens
    xor rdx, rdx
    mov rbx, 10
    div rbx
    add al, '0'
    stosb
    
    ; Units
    add dl, '0'
    mov al, dl
    stosb
    
    pop rdx
    pop rbx
    pop rax
    ret