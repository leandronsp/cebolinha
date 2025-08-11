# Cebolinha

For macOS using Lima:

```bash
$ limactl start --name ubuntu --arch x86_64 --rosetta --mount-writable --cpus 4 --disk 20
$ limactl shell ubuntu
$ sudo apt install nasm binutils gdb
$ nasm -f elf64 -o asm/server.o asm/server.asm
$ ld -o server asm/server.o
$ ./server
```

For macOS using Docker on Lima:

```bash
$ limactl start --name ubuntu --arch x86_64 --rosetta --mount-writable --cpus 4 --disk 20
$ limactl shell ubuntu
$ docker compose build
$ docker compose up
```
