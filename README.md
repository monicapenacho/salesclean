<<<<<<< HEAD
# SalesClean

> Pipeline DataOps para limpieza automatizada de datos de ventas, orquestado con Prefect, contenerizado con Docker y desplegado en Microsoft Azure mediante GitHub Actions.

[![CI](https://github.com/monicapenacho/salesclean/actions/workflows/ci.yml/badge.svg)](https://github.com/monicapenacho/salesclean/actions/workflows/ci.yml)
[![Pipeline](https://github.com/monicapenacho/salesclean/actions/workflows/pipeline.yml/badge.svg)](https://github.com/monicapenacho/salesclean/actions/workflows/pipeline.yml)
[![Coverage](https://img.shields.io/badge/coverage-%E2%89%A570%25-brightgreen)](./htmlcov/index.html)
[![Python](https://img.shields.io/badge/python-3.11-blue)](https://www.python.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## Tabla de contenidos

1. [Problema y solución](#1-problema-y-solución)
2. [Arquitectura](#2-arquitectura)
3. [Stack tecnológico](#3-stack-tecnológico)
4. [Quickstart (5 minutos)](#4-quickstart-5-minutos)
5. [Estructura del repositorio](#5-estructura-del-repositorio)
6. [Cómo ejecutar el pipeline](#6-cómo-ejecutar-el-pipeline)
7. [Tests y cobertura](#7-tests-y-cobertura)
8. [Despliegue en Azure](#8-despliegue-en-azure)
9. [Metodología ágil](#9-metodología-ágil)
10. [Documentación completa](#10-documentación-completa)

---

## 1. Problema y solución

**Problema.** Una tienda online recibe cada noche un fichero de ventas (`ventas_dia.xlsx`). Los datos llegan sucios: filas duplicadas, precios negativos o vacíos, cantidades nulas. Cada mañana, el equipo de analítica pierde **una hora** limpiando manualmente antes de poder construir el dashboard del día.

**Solución.** SalesClean automatiza ese trabajo: cada noche a las 02:00 UTC, un *flow* de Prefect ejecuta extracción → transformación → validación → carga en Azure Blob Storage, dejando los datos limpios y validados listos para Synapse Serverless SQL antes de que llegue el equipo. Métricas de calidad publicadas como manifiesto JSON en cada ejecución; alerta automática si la calidad cae por debajo del 95 %.

| Métrica | Antes | Con SalesClean |
|---|---|---|
| Tiempo manual diario | 60 min | 0 min |
| Tiempo de ejecución | n/a | < 45 s |
| Calidad de datos | ~85 % | ≥ 98 % |
| Trazabilidad | Ninguna | Logs + manifiesto JSON por ejecución |

---

## 2. Arquitectura

```
        ┌──────────────────┐
        │  Origen (CSV/    │
        │  XLSX subido a   │
        │  Blob raw)       │
        └────────┬─────────┘
                 │
                 ▼
   ┌─────────────────────────────┐
   │  GitHub Actions             │     trigger: cron diario 02:00 UTC
   │  pipeline.yml               │              o workflow_dispatch
   │  (autenticación OIDC)       │
   └────────────┬────────────────┘
                │ docker run salesclean:latest
                ▼
   ┌─────────────────────────────┐
   │  Prefect Flow               │
   │  ┌───────────────────────┐  │
   │  │ extract  (blob raw)   │  │
   │  │   ↓                   │  │
   │  │ transform (pandas)    │  │
   │  │   ↓                   │  │
   │  │ validate  (pandera)   │──┼──fail──▶ alerts (webhook)
   │  │   ↓                   │  │
   │  │ load   (blob curated) │  │
   │  │   ↓                   │  │
   │  │ manifest (métricas)   │  │
   │  └───────────────────────┘  │
   └────────────┬────────────────┘
                │
                ▼
        ┌──────────────────┐         ┌──────────────────┐
        │ Azure Blob       │ ──────▶ │ Synapse          │
        │ curated/         │         │ Serverless SQL   │
        │ (parquet)        │         │ (dashboard)      │
        └──────────────────┘         └──────────────────┘
```

Diagrama detallado y decisiones técnicas en [`docs/architecture.md`](docs/architecture.md).
ADRs (Architecture Decision Records) en [`docs/decisions/`](docs/decisions/).

---

## 3. Stack tecnológico

| Capa | Tecnología | Por qué |
|---|---|---|
| Lenguaje | Python 3.11 | Estándar de facto en data engineering, librerías maduras |
| Procesamiento | Pandas 2.2 | Suficiente para el volumen (~MB/día). Si crece a GB → migrar a Polars/Spark |
| Validación | Pandera 0.20 | Esquemas declarativos type-safe, mucho más mantenible que `if`s sueltos |
| Orquestación | Prefect 2.20 | 1 contenedor (vs 4-5 de Airflow), Python puro, gratis self-hosted |
| Cloud | Azure Blob Storage | Autorizado por el profesor; equivalente funcional a AWS S3 |
| Query analítico | Azure Synapse Serverless | Pay-per-query sobre Parquet en Blob, sin clúster que mantener |
| Contenedores | Docker + Compose | Reproducibilidad local idéntica a producción |
| CI/CD | GitHub Actions | Gratis para repos públicos, integrado con OIDC contra Azure |
| IaC | Terraform (provider azurerm) | Industria estándar; estado versionado en Blob |
| Tests | pytest + pytest-cov + Azurite | Mock 100 % local sin tocar Azure real |

---

## 4. Quickstart (5 minutos)

Requisitos previos: Docker Desktop, Make, Python 3.11, Git.

```bash
# 1. Clona el repo
git clone https://github.com/monicapenacho/salesclean.git
cd salesclean

# 2. Crea el .env desde la plantilla
make env

# 3. Arranca Azurite (Azure Blob simulado) + Prefect server
make up

# 4. Construye la imagen del pipeline
make build

# 5. Ejecuta el flow ETL
make run
```

Tras esto:

- Prefect UI: <http://localhost:4200>
- Logs del run: visibles en la UI o con `make logs`
- Datos limpios: contenedor `curated` en Azurite

---

## 5. Estructura del repositorio

```
salesclean/
├── src/salesclean/         # paquete Python (lógica pura, testeable)
├── flows/                  # flows Prefect (orquestación)
├── tests/                  # unit + integration (cobertura ≥ 70 %)
├── infra/                  # Terraform (Azure)
├── .github/workflows/      # CI/CD (4 workflows)
├── docs/                   # arquitectura, ADRs, memoria, sprints
├── data/                   # datos de ejemplo y fixtures
├── notebooks/              # análisis exploratorios
├── Dockerfile              # imagen multi-stage
├── docker-compose.yml      # entorno local (azurite + prefect)
├── pyproject.toml          # paquete + config ruff/black/pytest
├── Makefile                # atajos de desarrollo
└── README.md               # este archivo
```

Detalle de cada carpeta en [`docs/architecture.md`](docs/architecture.md).

---

## 6. Cómo ejecutar el pipeline

**En local (con Azurite):**
```bash
make up                    # arranca azurite + prefect-server
make run                   # ejecuta el ETL una vez
```

**En local sin Docker:**
```bash
make install               # instala el paquete + deps dev
make run-local             # ejecuta el flow con Python directo
```

**Manualmente desde GitHub Actions:**
- Ve a la pestaña *Actions* → *Pipeline SalesClean* → *Run workflow*.

**Programado:**
- Se ejecuta automáticamente cada día a las 02:00 UTC (cron en `.github/workflows/pipeline.yml`).

---

## 7. Tests y cobertura

```bash
make test                  # todos los tests + coverage
make test-unit             # solo unitarios (rápidos)
make test-integration      # solo integración
make coverage              # abre informe HTML
```

El umbral mínimo de cobertura es **70 %** (configurado en `pyproject.toml`); rompe el build si baja. Objetivo real del proyecto: **≥ 85 %**.

---

## 8. Despliegue en Azure

```bash
az login                                      # autentica con tu cuenta Azure
cd infra
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Recursos creados: Resource Group, Storage Account con dos contenedores (`raw`, `curated`), Service Principal con permisos mínimos para GitHub Actions (OIDC), Action Group para alertas. Detalle completo en [`docs/runbook.md`](docs/runbook.md).

---

## 9. Metodología ágil

Proyecto desarrollado en **Scrum** durante 3 sprints de 1 semana, equipo de 4 personas (2 data engineers + 1 analyst + 1 QA).

- [`docs/agile/product_backlog.md`](docs/agile/product_backlog.md) — User stories priorizadas
- [`docs/agile/sprint_1.md`](docs/agile/sprint_1.md) — *Setup & MVP local*
- [`docs/agile/sprint_2.md`](docs/agile/sprint_2.md) — *Cloud & CI/CD*
- [`docs/agile/sprint_3.md`](docs/agile/sprint_3.md) — *Calidad, alertas & memoria*
- [`docs/agile/retrospectives.md`](docs/agile/retrospectives.md) — Retrospectivas

Tablero Kanban en GitHub Projects (link en el repo).

---

## 10. Documentación completa

- [Memoria del proyecto](docs/memoria.md) (10 páginas)
- [Arquitectura detallada](docs/architecture.md)
- [Decisiones técnicas (ADRs)](docs/decisions/)
- [Runbook operacional](docs/runbook.md)
- [Q&A para defensa](docs/defense_qa.md)

---

## Autoría

Mónica Penacho Collado — *Universidad Internacional de Valencia (VIU)* — *20GIAR Metodologías de desarrollo y despliegue de aplicaciones para ciencia de datos* — Curso 2025/2026.

Licencia [MIT](LICENSE).
=======
# salesclean
salesclean
>>>>>>> bcd7e982fbace6a12445cc37d37d8869fa31baa2
