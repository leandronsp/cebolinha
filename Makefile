SHELL = /bin/bash
.ONESHELL:
.DEFAULT_GOAL: help

help: ## Show all available commands
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n"} /^[.a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development Environment

processors.up: ## Start the payment processor service
	docker compose -f docker-compose.processor.yml up -d

processors.down: ## Stop the payment processor service
	docker compose -f docker-compose.processor.yml down --remove-orphans

start.dev: ## Start the development environment
	@make processors.up
	@docker compose up -d nginx

compose.down: ## Stop all services and remove containers
	@docker compose down --remove-orphans

compose.logs: ## View logs for all services
	@docker compose logs -f

##@ Testing

processors.test: ## Test payment processor endpoints
	@./scripts/test-health.sh
	@./scripts/test-processors.sh

api.test.payments: ## Test POST /payments endpoint via nginx
	@./scripts/test-api-payments.sh

api.test.summary: ## Test GET /payments-summary endpoint via nginx
	@./scripts/test-api-summary.sh

api.test.e2e: ## Run end-to-end tests for the API
	@./scripts/e2e.sh

rinha: ## Run k6 performance test (Rinha de Backend)
	@./scripts/reset.sh
	@./scripts/rinha.sh

rinha.official: ## Run official Rinha test with scoring
	@./scripts/reset.sh
	@./scripts/run-local-test.sh

##@ Build & Deploy

docker.build: ## Build docker images for ASM API and Go worker
	@docker build -t leandronsp/cebolinha-api --target asm-api --platform linux/amd64 .
	@docker build -t leandronsp/cebolinha-worker --target go-worker --platform linux/amd64 .

docker.push: ## Push docker images to registry
	@docker push leandronsp/cebolinha-api
	@docker push leandronsp/cebolinha-worker

##@ Service Development (use make -C api <target> or make -C worker <target>)

api.help: ## Show assembly API commands
	@make -C api help

worker.help: ## Show Go worker commands  
	@make -C worker help

# Convenience targets that delegate to service Makefiles
api.build: ## Build assembly server
	@make -C api build

api.run: ## Build and run assembly server
	@make -C api run

api.debug: ## Debug assembly server with GDB
	@make -C api debug

api.clean: ## Clean assembly build artifacts
	@make -C api clean

worker.build: ## Build Go worker
	@make -C worker build

worker.run: ## Build and run Go worker
	@make -C worker run

worker.test: ## Run Go worker tests
	@make -C worker test

worker.clean: ## Clean Go worker artifacts
	@make -C worker clean