FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py ./

ENV PORT=8081
ENV PYTHONUNBUFFERED=1
EXPOSE 8081

CMD ["sh", "-c", "celery -A app.celery_app worker --loglevel=${LOG_LEVEL:-info} & uvicorn app:health_app --host 0.0.0.0 --port ${PORT:-8081}"]
