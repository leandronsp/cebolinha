# Simple dynamic Makefile for Cebolinha assembly modules

SOURCES = $(wildcard asm/*.asm)
OBJECTS = $(SOURCES:asm/%.asm=build/%.o)

all: bin/server

build/%.o: asm/%.asm
	nasm -f elf64 -o $@ $<

bin/server: $(OBJECTS)
	ld -o $@ $^

run: bin/server
	./bin/server

.PHONY: all run
