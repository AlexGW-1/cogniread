import os
from typing import Dict

from celery import Celery
from fastapi import FastAPI

REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
QUEUE_NAME = os.getenv("AI_WORKER_QUEUE", "ai-tasks")
LOG_LEVEL = os.getenv("LOG_LEVEL", "info")

celery_app = Celery("worker", broker=REDIS_URL, backend=REDIS_URL)
celery_app.conf.task_default_queue = QUEUE_NAME

health_app = FastAPI()


@health_app.get("/health")
def health() -> Dict[str, str]:
    return {"status": "ok"}


@celery_app.task(name="worker.process_text")
def process_text(text: str) -> Dict[str, int]:
    return {"length": len(text)}
