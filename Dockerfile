# ---- build stage: resolve dependencies into a venv ----
FROM python:3.13-alpine AS builder

WORKDIR /app

# Pick up security updates published after the base image was tagged
RUN apk upgrade --no-cache

# Install uv for faster package management (musl build, to match the alpine base)
COPY --from=ghcr.io/astral-sh/uv:alpine /usr/local/bin/uv /usr/local/bin/uv

# Copy dependency files and README (required by pyproject.toml)
COPY pyproject.toml uv.lock README.md ./

# Install dependencies only (not the app itself)
ENV UV_PROJECT_ENVIRONMENT=/opt/venv
RUN uv sync --frozen --no-install-project

# ---- runtime stage: the app and its venv, without the build tooling ----
FROM python:3.13-alpine

WORKDIR /app

# Unbuffered Python output (for Docker logs)
ENV PYTHONUNBUFFERED=1

# Enable web auth mode for Docker (binds OAuth to 0.0.0.0)
ENV WEB_AUTH=true

# Pick up security updates published after the base image was tagged
RUN apk upgrade --no-cache

# The python base image ships setuptools 70.3.0, and CVE-2025-47273 is fixed in
# 78.1.1. Nothing here imports it - the app runs from /opt/venv - but a flagged
# package left in the runtime layer is a finding all the same.
RUN python -m pip install --no-cache-dir --upgrade 'setuptools>=78.1.1'

# Take the resolved venv, and leave uv behind in the builder. It lives outside
# /app so the COPY below cannot clobber it with a venv from the build context.
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Copy application
COPY . .

# Remove any existing tokens (user should mount their own)
RUN rm -f token.json

# Expose ports: 8766 for web UI, 8767 for OAuth callback
EXPOSE 8766 8767

# Run straight from the prebuilt venv - no dependency resolution at startup
CMD ["python", "main.py"]
