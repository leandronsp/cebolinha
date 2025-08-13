# Simple dynamic Makefile for Cebolinha assembly modules

SOURCES = $(wildcard asm/*.asm)
OBJECTS = $(SOURCES:asm/%.asm=build/%.o)

build/%.o: asm/%.asm | build
	nasm -f elf64 -o $@ $<

bin/server: $(OBJECTS) | bin
	ld -o $@ $^

build bin:
	mkdir -p $@

run: bin/server
	./bin/server

clean: 
	rm -rf build bin

.PHONY: all run
