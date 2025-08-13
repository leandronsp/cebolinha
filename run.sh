#!/bin/bash

# Build the server
nasm -f elf64 -o build/server.o asm/server.asm
ld -o bin/server build/server.o

# Run the server
./bin/server
