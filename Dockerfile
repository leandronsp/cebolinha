# Build stage for Rust Worker Only
FROM --platform=linux/amd64 rust AS rust-build
WORKDIR /app
COPY Cargo.toml Cargo.lock* ./
RUN cargo build --release --bin worker || echo "Initial build may fail - OK"
COPY src src
RUN cargo build --release --bin worker

# Build stage for Assembly
FROM --platform=linux/amd64 ubuntu:22.04 AS asm-build
WORKDIR /app
RUN apt-get update && \
    apt-get install -y nasm binutils make && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
COPY asm asm
COPY Makefile.asm ./Makefile
RUN mkdir -p build bin
RUN make

# ASM API target
FROM --platform=linux/amd64 debian:stable-slim AS asm-api
WORKDIR /app
COPY --from=asm-build /app/bin/server /app/bin/server
EXPOSE 3000
CMD ["/app/bin/server"]

# Rust Worker target  
FROM --platform=linux/amd64 debian:stable-slim AS rust-worker
WORKDIR /app
COPY --from=rust-build /app/target/release/worker /usr/bin/worker
CMD ["worker"]
