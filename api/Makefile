SHELL = /bin/bash
.ONESHELL:
.DEFAULT_GOAL: help

help: ## Show available assembly commands
	@awk 'BEGIN {FS = ":.*##"; printf "Assembly API Commands:\n"} /^[.a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

# Assembly source and object files
ASM_SOURCES = $(wildcard *.asm)
ASM_OBJECTS = $(ASM_SOURCES:%.asm=build/%.o)

clean: ## Clean assembly build artifacts
	@rm -rf build bin

# Pattern rule for building assembly objects
build/%.o: %.asm | build
	@nasm -g -F dwarf -f elf64 -o $@ $<

# Build the server binary from all object files
bin/server: $(ASM_OBJECTS) | bin
	@ld -g -o $@ $^

# Create build directories
build bin:
	@mkdir -p $@

build: bin/server ## Build assembly server

run: build ## Build and run assembly server
	@./bin/server

debug: build ## Build and debug assembly server with GDB
	@gdb -q -x ../debug_http.gdb bin/server