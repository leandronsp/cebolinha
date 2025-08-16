# 🧅 Cebolinha

A minimalist HTTP server in pure x86-64 Assembly + Go workers for the [Rinha de Backend 2025](https://github.com/zanfranceschi/rinha-de-backend-2025).

## Architecture

- **Assembly HTTP API**: Single-threaded server written in pure x86-64 assembly (no libc)
- **Go Workers**: Asynchronous payment processing with retry logic and fallback
- **Redis**: Message queue and data storage
- **NGINX**: Load balancer

## Requirements

- Docker
- Make
- Força de vontade (optional)

## Quick Start

```bash
# Setup and start all services
make processors.up
make start.dev

# Test the API (via NGINX on port 9999)
make api.test.payments    # Test POST /payments
make api.test.summary      # Test GET /payments-summary
```

## Commands

### Payment Processors
```bash
make processors.up         # Start payment processors
make processors.down       # Stop payment processors
make processors.test       # Test processor endpoints
make processors.purge      # Clear processor data
```

### API Development
```bash
make start.dev             # Start development environment
make compose.logs          # View logs
make compose.down          # Stop all services
```

### API Testing
```bash
make api.test.payments     # Test POST /payments endpoint
make api.test.summary      # Test GET /payments-summary endpoint
make api.test.purge        # Test POST /purge-payments endpoint
make api.test.e2e          # Run end-to-end tests
```

### Performance Testing
```bash
make rinha                 # Run k6 performance test
make rinha.official        # Run official Rinha test with scoring
```

### Build & Deploy
```bash
make docker.build          # Build Docker images
make docker.push           # Push images to registry
```

## Assembly Development

```bash
make asm.build             # Build assembly server
make asm.run               # Run assembly server locally
make asm.debug             # Debug with GDB
make asm.clean             # Clean build artifacts
```

## Go Development

```bash
make go.build              # Build Go worker
make go.run                # Run Go worker locally
make go.test               # Run tests
make go.fmt                # Format code
```
