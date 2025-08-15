# 🐑 Ovelha

Mais uma submissão para a [Rinha de Backend 2025](https://github.com/zanfranceschi/rinha-de-backend-2025), desta vez em Rust.

## Requisitos

- Docker
- Make
- Força de vontade

## Setup

```bash
make api.setup
```

## Comandos úteis

### Gerenciamento dos Processadores de Pagamento

```bash
# Iniciar processadores de pagamento
make processors.up

# Testar endpoints dos processadores
make processors.test

# Limpar dados dos processadores
make processors.purge

# Parar processadores
make processors.down
```

### Desenvolvimento da API

```bash
# Iniciar ambiente de desenvolvimento
make start.dev

# Testar endpoints da API via NGINX (localhost:9999)
make api.test.payments
make api.test.summary
make api.test.purge

# Ver logs
make compose.logs

# Parar todos os serviços
make compose.down
```

### Teste de Performance

```bash
# Executar teste k6 (Rinha de Backend)
make rinha
```

<img width="380" height="561" alt="Screenshot 2025-08-08 at 19 34 02" src="https://github.com/user-attachments/assets/cff932bd-0f65-4fa6-95f4-1631c6bbb809" />


> Até que Rust escala, né?
