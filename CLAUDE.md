# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is "Cebolinha" - a pure x86-64 assembly HTTP server that demonstrates low-level systems programming. The server implements a basic HTTP/1.1 web server using only Linux system calls, without any external libraries or frameworks.

## Architecture

The server has been modularized from a single assembly file into a clean, maintainable structure:

### Modular Structure
```
asm/
├── server.asm       # Main server coordination and control flow
├── timer.asm        # Sleep/timing operations
├── sync.asm         # Mutex and condition variable primitives
├── queue.asm        # Thread-safe queue management
├── network.asm      # Socket operations (create, bind, listen, accept)
├── http.asm         # HTTP response generation and connection handling
├── threading.asm    # Thread creation and stack management
└── include/
    ├── syscalls.inc # Linux system call numbers
    └── common.inc   # Shared constants (QUEUE_OFFSET_CAPACITY, THREAD_POOL_SIZE)
```

### Key Features
- **Multi-threaded HTTP server**: Thread pool with 5 worker threads using Linux clone() syscalls
- **Custom thread synchronization**: Mutex and condition variables using futex syscalls
- **Dynamic queue management**: Thread-safe queue with automatic resizing using brk() syscalls
- **Pure syscall implementation**: No libc dependencies - all functionality via direct Linux syscalls
- **Modular design**: Each module has single responsibility with clear interfaces

### Server Components
- Socket creation, binding, and listening on port 3000
- Thread pool management with custom threading primitives
- Producer-consumer pattern with work queue for connection handling
- HTTP response generation (returns "Hello, World!" HTML page)

## Build Commands

### Using Makefile (Recommended)
```bash
make clean      # Clean build artifacts
make            # Build the server
make run        # Build and run the server
```

### Manual Build on Linux (requires NASM and binutils)
```bash
# Build all modules
nasm -f elf64 -o build/server.o asm/server.asm
nasm -f elf64 -o build/timer.o asm/timer.asm
nasm -f elf64 -o build/sync.o asm/sync.asm
nasm -f elf64 -o build/queue.o asm/queue.asm
nasm -f elf64 -o build/network.o asm/network.asm
nasm -f elf64 -o build/http.o asm/http.asm
nasm -f elf64 -o build/threading.o asm/threading.asm
# Link all object files
ld -o bin/server build/*.o
./bin/server
```

### macOS Development (using Lima)
Since the server targets Linux x86-64, macOS development requires a Linux VM:

#### Native Assembly Build
```bash
limactl start --name ubuntu --arch x86_64 --rosetta --mount-writable --cpus 4 --disk 20
limactl shell ubuntu
sudo apt install nasm binutils gdb
nasm -f elf64 -o asm/server.o asm/server.asm
ld -o server asm/server.o
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
docker build -t cebolinha .
docker run -p 3000:3000 cebolinha
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
- The server runs on port 3000 and serves a simple "Hello, World!" HTML response
- Thread pool size is configurable via `THREAD_POOL_SIZE` in `common.inc`
- Queue capacity grows dynamically by `QUEUE_OFFSET_CAPACITY` bytes
- Memory management is manual using brk() syscalls for queue expansion
- No external dependencies - completely self-contained assembly implementation

### Module Interface Guidelines
- **timer.asm**: Exports `timer_sleep` - preserves all registers
- **sync.asm**: Exports mutex/condvar functions - uses futex syscalls
- **queue.asm**: Expects `r8` for enqueue input, returns `rax` from dequeue
- **network.asm**: Socket functions operate on global `sockfd`
- **http.asm**: Expects file descriptor in `r10` for response operations
- **threading.asm**: Takes handler address in `rdi`, creates thread with stack

## System Requirements

- Linux x86-64 system
- NASM assembler
- GNU binutils (ld linker)
- Docker (for containerized builds)

The Dockerfile handles all build dependencies automatically for containerized deployment.
