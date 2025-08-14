# Simple dynamic Makefile for Cebolinha assembly modules

SOURCES = $(wildcard asm/*.asm)
OBJECTS = $(SOURCES:asm/%.asm=build/%.o)

build/%.o: asm/%.asm | build
	nasm -g -F dwarf -f elf64 -o $@ $<

bin/server: $(OBJECTS) | bin
	ld -g -o $@ $^

build bin:
	mkdir -p $@

run: bin/server
	./bin/server

debug: bin/server
	gdb -q -x debug_http.gdb bin/server

clean: 
	rm -rf build bin

.PHONY: all run debug
