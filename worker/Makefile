SHELL = /bin/bash
.ONESHELL:
.DEFAULT_GOAL: help

help: ## Show available Go worker commands
	@awk 'BEGIN {FS = ":.*##"; printf "Go Worker Commands:\n"} /^[.a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

build: ## Build Go worker binary
	@go build -o worker .

run: build ## Build and run Go worker locally
	@./worker

clean: ## Clean Go build artifacts
	@rm -f worker

test: ## Run Go tests
	@go test .

fmt: ## Format Go code
	@go fmt .

mod.tidy: ## Tidy Go module dependencies
	@go mod tidy