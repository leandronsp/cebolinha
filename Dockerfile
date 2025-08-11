# Stage 1: Build
FROM --platform=linux/amd64 ubuntu:25.04 AS builder
RUN apt-get update && apt-get install -y \
    nasm \
    binutils \
    gcc \
    libc6-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY asm/ ./asm/
RUN cd asm && \
    nasm -f elf64 -o server.o server.asm && \
    ld -o server server.o

# Stage 2: Runtime
FROM --platform=linux/amd64 ubuntu:25.04 AS runtime
RUN apt-get update && apt-get install -y \
    libc6 \
    libssl3 \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/asm/server /app/server
EXPOSE 3000
CMD ["sh", "-c", "/app/server"]
