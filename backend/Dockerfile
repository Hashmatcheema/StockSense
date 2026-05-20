# StockSense backend — FastAPI + aiosqlite + APScheduler.
# Multi-stage to keep the runtime image small.
FROM python:3.11-slim AS build
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
# Non-root user — least-privilege.
RUN useradd -m -u 1000 stocksense
COPY --from=build /root/.local /home/stocksense/.local
COPY --chown=stocksense:stocksense . /app
ENV PATH=/home/stocksense/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1
USER stocksense
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health').status == 200 else 1)"
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
