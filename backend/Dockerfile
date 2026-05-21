# StockSense backend — FastAPI + aiosqlite + APScheduler.
# Build context: stock_sense/ (one level above backend/).
# Multi-stage to keep the runtime image small.
FROM python:3.11-slim AS build
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.11-slim
WORKDIR /app
# Non-root user — least-privilege.
RUN useradd -m -u 1000 stocksense
COPY --from=build /root/.local /home/stocksense/.local
COPY --chown=stocksense:stocksense backend/ /app/
COPY --chown=stocksense:stocksense scenarios/ /app/scenarios/
ENV PATH=/home/stocksense/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    SCENARIOS_DIR=/app/scenarios
USER stocksense
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD python -c "import urllib.request,os,sys; port=os.environ.get('PORT','8000'); sys.exit(0 if urllib.request.urlopen(f'http://127.0.0.1:{port}/health').status==200 else 1)"
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
