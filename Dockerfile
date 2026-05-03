# =============================================================================
# SalesClean - imagen del pipeline (multi-stage para reducir tamaño)
# =============================================================================

# ---------- Stage 1: builder ----------
FROM python:3.11-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

# Instala dependencias del sistema necesarias para compilar pyarrow, pandas, etc.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Copia y construye un wheelhouse (capa cacheable)
COPY requirements.txt .
RUN pip wheel --wheel-dir /wheels -r requirements.txt

# ---------- Stage 2: runtime ----------
FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PATH="/home/app/.local/bin:${PATH}"

# Crea usuario no-root (buena práctica de seguridad)
RUN groupadd --system app && \
    useradd --system --gid app --create-home --home-dir /home/app app

WORKDIR /app

# Copia los wheels desde el stage builder e instala
COPY --from=builder /wheels /wheels
COPY requirements.txt .
RUN pip install --user --no-index --find-links=/wheels -r requirements.txt && \
    rm -rf /wheels

# Copia el código del proyecto
COPY --chown=app:app pyproject.toml README.md ./
COPY --chown=app:app src/ ./src/
COPY --chown=app:app flows/ ./flows/

# Instala el paquete en modo editable
RUN pip install --user -e .

USER app

# Healthcheck simple: importa el paquete
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD python -c "import salesclean; print('ok')" || exit 1

# Por defecto, ejecuta el flow
CMD ["python", "-m", "flows.etl_flow"]
