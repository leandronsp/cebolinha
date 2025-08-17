# Dinossauro

```
______   _________ _        _______  _______  _______  _______  _        _______  _______ 
(  __  \ \__   __/( (    /|(  ___  )(  ____ \(  ____ \(  ___  )| \    /\(  ____ \(  ___  )
| (  \  )   ) (   |  \  ( || (   ) || (    \/| (    \/| (   ) ||  \  / /| (    \/| (   ) |
| |   ) |   | |   |   \ | || |   | || (_____ | (_____ | (___) ||  (_/ / | (__    | |   | |
| |   | |   | |   | (\ \) || |   | |(_____  )(_____  )|  ___  ||   _ (  |  __)   | |   | |
| |   ) |   | |   | | \   || |   | |      ) |      ) || (   ) ||  ( \ \ | (      | |   | |
| (__/  )___) (___| )  \  || (___) |/\____) |/\____) || )   ( ||  /  \ \| (____/\| (___) |
(______/ \_______/|/    )_)(_______)\_______)\_______)|/     \||_/    \/(_______/(_______)
```

Mais uma submissão para a [Rinha de Backend 2025](https://github.com/zanfranceschi/rinha-de-backend-2025), desta vez em **x86-64 Assembly + Go**.

## Stack

* x86-64 Assembly HTTP Server (NASM)
* Go 1.25+ Worker
* Redis
* NGINX

## Estratégias

* Load balancing com NGINX, utilizando configuração otimizada para alta concorrência
* **HTTP server puro em x86-64 Assembly** utilizando apenas syscalls Linux - sem bibliotecas externas
* Thread pool artesanal implementado em Assembly com 5 threads worker
* Processamento assíncrono com Go worker + Redis pub/sub
* Armazenamento do resumo de pagamentos no Redis utilizando contadores globais
* **Filtro de data via query parameters** implementado diretamente em Assembly (ISO8601 compatível)
* Pool de conexões para o Redis no worker Go
* Implementação RESP (Redis Serialization Protocol) em Assembly puro
* Retry automático no worker com backoff configurável:
    - 5 tentativas padrão com timeout de 3.5s
    - 1 tentativa fallback com timeout de 5.5s
    - Reprocessamento via pub/sub em caso de falha de ambos processadores

## Arquitetura Única

Este projeto implementa um **HTTP server completo em x86-64 Assembly**, algo extremamente raro no ecosistema web moderno. Toda a stack de rede (sockets, parsing HTTP, protocolo Redis) é implementada via syscalls diretos do Linux, sem dependências externas.

O Assembly lida com:
- Criação e gerenciamento de sockets TCP
- Parsing completo de requests HTTP/1.1 (verb, path, headers, body, query parameters)
- Roteamento de rotas (`POST /payments`, `GET /payments-summary`)
- Comunicação direta com Redis via protocolo RESP
- Thread pool e sincronização via futex
- Filtros de data para compliance com a Rinha

----

Repositório: [leandronsp/dinossauro](https://github.com/leandronsp/dinossauro)
Github: [leandronsp](https://github.com/leandronsp)
DEV.to: [leandronsp](https://dev.to/leandronsp)
LinkedIn: [leandronsp](https://linkedin.com/leandronsp)
Twitter: [@leandronsp](https://twitter.com/leandronsp)
Bluesky: [@leandronsp](http://bsky.app/leandronsp)
Mastodon: [@leandronsp](https://mastodon.social/@leandronsp)