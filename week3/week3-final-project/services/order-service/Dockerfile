FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

FROM python:3.11-slim
RUN groupadd -r appgroup && useradd -r -g appgroup -u 10002 appuser
RUN apt-get update && apt-get install -y --no-install-recommends curl && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY --from=builder /install /usr/local
COPY --chown=appuser:appgroup main.py .
USER appuser
EXPOSE 8001
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -sf http://localhost:8001/health || exit 1
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
