# Build stage for Go Worker
FROM --platform=linux/amd64 golang:1.25-alpine AS go-build
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY cmd cmd
COPY internal internal
RUN CGO_ENABLED=0 GOOS=linux go build -o worker cmd/worker/main.go

# Build stage for Assembly
FROM --platform=linux/amd64 ubuntu:22.04 AS asm-build
WORKDIR /app
RUN apt-get update && \
    apt-get install -y nasm binutils make && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*
COPY asm asm
COPY Makefile ./
RUN mkdir -p build bin
RUN make asm.build

# ASM API target
FROM --platform=linux/amd64 debian:stable-slim AS asm-api
WORKDIR /app
COPY --from=asm-build /app/bin/server /app/bin/server
EXPOSE 3000
CMD ["/app/bin/server"]

# Go Worker target  
FROM --platform=linux/amd64 alpine:latest AS go-worker
RUN apk --no-cache add ca-certificates
WORKDIR /app
COPY --from=go-build /app/worker /usr/bin/worker
CMD ["worker"]
