# =============================================================================
# SalesClean - atajos para desarrollo y demo
# Uso: `make <target>`. Ejecuta `make help` para ver todos los comandos.
# =============================================================================

.DEFAULT_GOAL := help
SHELL := /bin/bash

# --- Variables ---
PY      := python
PIP     := pip
COMPOSE := docker compose

# --- Targets ---

.PHONY: help
help: ## Muestra esta ayuda
	@echo "SalesClean - comandos disponibles:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# --- Setup local ---

.PHONY: install
install: ## Instala el paquete + deps de desarrollo en el venv actual
	$(PIP) install --upgrade pip
	$(PIP) install -e ".[dev]"

.PHONY: env
env: ## Crea .env desde la plantilla si no existe
	@test -f .env || (cp .env.example .env && echo "Creado .env - revisa y rellena valores")

# --- Calidad de código ---

.PHONY: lint
lint: ## Ejecuta ruff (linter)
	ruff check src flows tests

.PHONY: format
format: ## Formatea código con black + ruff
	black src flows tests
	ruff check --fix src flows tests

.PHONY: typecheck
typecheck: ## Ejecuta mypy (type checking)
	mypy src

# --- Tests ---

.PHONY: test
test: ## Lanza tests con coverage (falla si <70%)
	pytest

.PHONY: test-unit
test-unit: ## Solo tests unitarios (rápidos)
	pytest -m unit

.PHONY: test-integration
test-integration: ## Solo tests de integración
	pytest -m integration

.PHONY: coverage
coverage: test ## Genera y abre el informe HTML de cobertura
	@python -c "import webbrowser; webbrowser.open('htmlcov/index.html')" 2>/dev/null || true

# --- Docker / entorno local ---

.PHONY: build
build: ## Construye la imagen Docker
	$(COMPOSE) build pipeline

.PHONY: up
up: env ## Arranca Azurite + Prefect server en background
	$(COMPOSE) up -d azurite prefect-server
	@echo ""
	@echo "Prefect UI:  http://localhost:4200"
	@echo "Azurite:     http://localhost:10000"

.PHONY: down
down: ## Para todos los servicios
	$(COMPOSE) down

.PHONY: logs
logs: ## Sigue los logs de todos los servicios
	$(COMPOSE) logs -f

# --- Pipeline ---

.PHONY: run
run: ## Ejecuta el flow ETL contra el entorno local (Azurite)
	$(COMPOSE) run --rm pipeline

.PHONY: run-local
run-local: ## Ejecuta el flow directamente con Python (sin Docker)
	$(PY) -m flows.etl_flow

# --- Terraform ---

.PHONY: tf-init
tf-init: ## Inicializa Terraform en infra/
	cd infra && terraform init

.PHONY: tf-plan
tf-plan: ## Muestra el plan de cambios de Terraform
	cd infra && terraform plan

.PHONY: tf-apply
tf-apply: ## Aplica la infraestructura en Azure (requiere `az login`)
	cd infra && terraform apply

# --- Limpieza ---

.PHONY: clean
clean: ## Borra cachés, builds y artefactos de coverage
	rm -rf build/ dist/ *.egg-info src/*.egg-info
	rm -rf .pytest_cache .mypy_cache .ruff_cache
	rm -rf htmlcov .coverage coverage.xml
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete

.PHONY: clean-all
clean-all: clean down ## Limpia todo + para contenedores + borra volúmenes Docker
	$(COMPOSE) down -v
