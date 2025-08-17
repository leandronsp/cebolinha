# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is "Dinossauro" - a pure x86-64 assembly HTTP server that demonstrates low-level systems programming. The server implements a basic HTTP/1.1 web server using only Linux system calls, without any external libraries or frameworks.

## Architecture

The server has been modularized from a single assembly file into a clean, maintainable structure:

### Project Structure
```
api/
├── server.asm       # Main server coordination and control flow (single-threaded)
├── network.asm      # Socket operations (create, bind, listen, accept)
├── http.asm         # HTTP request/response parsing and handling
├── handler.asm      # Route matching and request handling
├── redis.asm        # Redis client with RESP protocol implementation
├── include/
│   └── syscalls.inc # Linux system call numbers
├── build/           # Generated object files
└── bin/             # Generated binaries

worker/
├── main.go          # Worker entry point and coordination
├── config.go        # Configuration management
├── processor.go     # Payment processing logic
└── store.go         # Redis data operations
```

### Key Features
- **Single-threaded HTTP server**: Simple accept loop handling one connection at a time
- **HTTP request parsing**: Full HTTP/1.1 request parsing (verb, path, headers, body)
- **REST API routing**: POST /payments endpoint with JSON body handling
- **Redis integration**: Direct Redis RESP protocol client for message publishing
- **Pure syscall implementation**: No libc dependencies - all functionality via direct Linux syscalls
- **Modular design**: Each module has single responsibility with clear interfaces
- **Go worker system**: Separate Go workers handle payment processing with retry logic

### Server Components
- Socket creation, binding, and listening on port 3000
- Simple single-threaded accept loop for connection handling
- HTTP request parsing (verb, path, Content-Length header, body)
- Route matching and handling (POST /payments, GET /payments-summary)
- Redis client with RESP protocol for publishing JSON payloads
- Error handling with proper HTTP status codes (200, 404, 500)
- Go worker system for asynchronous payment processing with fallback logic

## Build Commands

### Using Makefile (Recommended)
```bash
make clean      # Clean build artifacts
make            # Build the server
make run        # Build and run the server
make debug      # Build and run with GDB debugger
```

### Manual Build on Linux (requires NASM and binutils)
```bash
# Build all modules
nasm -f elf64 -o api/build/server.o api/server.asm
nasm -f elf64 -o api/build/network.o api/network.asm
nasm -f elf64 -o api/build/http.o api/http.asm
nasm -f elf64 -o api/build/handler.o api/handler.asm
nasm -f elf64 -o api/build/redis.o api/redis.asm
# Link all object files
ld -o api/bin/server api/build/*.o
./api/bin/server
```

### macOS Development (using Lima)
Since the server targets Linux x86-64, macOS development requires a Linux VM:

#### Native Assembly Build
```bash
limactl start --name ubuntu --arch x86_64 --rosetta --mount-writable --cpus 4 --disk 20
limactl shell ubuntu
sudo apt install nasm binutils gdb
nasm -f elf64 -o api/server.o api/server.asm
ld -o server api/server.o
./server
```

#### Docker Build in Lima VM (Recommended)
```bash
limactl start --name ubuntu --arch x86_64 --rosetta --mount-writable --cpus 4 --disk 20
limactl shell ubuntu
docker compose build
docker compose up
```

### Docker Build and Run (Direct on macOS)
```bash
# Build and run with Docker Compose (may hang on Apple Silicon due to emulation)
docker-compose up --build

# Manual Docker build
docker build -t dinossauro .
docker run -p 3000:3000 dinossauro
```

**Note**: Direct Docker on Apple Silicon may cause the server to hang due to x86-64 emulation issues with complex threading. Use the Lima VM approach for reliable execution.

## Development Notes

### Modularization Best Practices
When working on this codebase:
- **Keep modules focused**: Each module should have a single, clear responsibility
- **Use include files**: System calls in `syscalls.inc`, shared constants in `common.inc`
- **Test incrementally**: After extracting each module, verify the server still works
- **Avoid premature abstraction**: Simple, direct function extraction works better than complex abstractions
- **Preserve register usage**: Be careful with register preservation across module boundaries

### Technical Details
- The assembly server runs on port 3000 and handles HTTP requests
- Single-threaded design for simplicity and reliability
- Memory management uses direct Linux syscalls (no libc dependencies)
- Go workers handle payment processing asynchronously through Redis
- No external dependencies in assembly code - completely self-contained implementation

### Module Interface Guidelines
- **server.asm**: Main entry point - simple single-threaded accept loop
- **network.asm**: Socket functions operate on global `sockfd`
- **http.asm**: 
  - Expects file descriptor in `r10` for response operations
  - Exports global variables: `verb_ptr`, `verb_len`, `path_ptr`, `path_len`, `body_ptr`, `body_len`
  - Functions: `parse_request`, `parse_headers`, `send_response`, `send_not_found_response`
- **handler.asm**: Route matching and handling - returns success/failure in `rax`
- **redis.asm**: 
  - `redis_publish_body(body_ptr, body_len)` - publishes JSON to Redis "payments" channel
  - Uses stack-based parameters: `rsi` = body_ptr, `rdx` = body_len
  - Returns 1 for success, 0 for failure

## API Testing

### POST /payments Endpoint
The server implements a REST API endpoint for payment processing:

```bash
# Test with curl
curl -X POST \
  -H "Content-Type: application/json" \
  -d '{
    "correlationId": "123e4567-e89b-12d3-a456-426614174000",
    "amount": 42.50,
    "requestedAt": "2025-01-15T10:30:00.000Z"
  }' \
  http://localhost:3000/payments
```

**Responses:**
- `200 OK`: `{"message":"enqueued"}` - Successfully published to Redis
- `500 Internal Server Error`: `{"error":"Redis publish failed"}` - Redis connection failed
- `404 Not Found`: `{"error":"Not Found"}` - All other routes

### Redis Integration
The server publishes JSON payloads directly to Redis using the RESP protocol:
- Channel: `payments`
- Payload: Raw JSON body from HTTP request
- No JSON parsing in assembly - passes through as-is

## Debugging

### GDB Debugging Assembly
```bash
make debug                                   # Start with GDB
(gdb) break api/redis.asm:158               # Set breakpoint in Redis function
(gdb) info registers                        # View all registers
(gdb) x/s $rsi                              # View string at register
(gdb) x/14c $rsi                            # View 14 characters
(gdb) print/x $rax                          # View register in hex
```

### Common Assembly Debugging Patterns
- **Register inspection**: `info registers`, `print $rax`
- **Memory examination**: `x/s address`, `x/10c address`, `x/8x address`
- **Stack inspection**: `x/8x $rsp` to see stack contents
- **Step execution**: `stepi` for single instruction, `nexti` for next instruction

### Register Corruption Debugging
Watch for these common issues:
- **Stack misalignment**: `push`/`pop` mismatch causing wrong values
- **String instruction side effects**: `rep movsb` modifies `rcx`, `rsi`, `rdi`
- **Function call preservation**: Save/restore registers across calls
- **Parameter passing**: Stack-based vs register-based parameter conflicts

## System Requirements

- Linux x86-64 system
- NASM assembler
- GNU binutils (ld linker)
- Redis server (for testing POST /payments)
- Docker (for containerized builds)

The Dockerfile handles all build dependencies automatically for containerized deployment.
