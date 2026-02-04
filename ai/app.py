import hashlib
import os
from typing import List

from celery import Celery
from fastapi import FastAPI
from pydantic import BaseModel, Field

app = FastAPI()

REDIS_URL = os.getenv("REDIS_URL", "redis://redis:6379/0")
QUEUE_NAME = os.getenv("AI_WORKER_QUEUE", "ai-tasks")
EMBEDDINGS_DIM = int(os.getenv("EMBEDDINGS_DIM", "16"))

celery_app = Celery("ai", broker=REDIS_URL, backend=REDIS_URL)
celery_app.conf.task_default_queue = QUEUE_NAME


class EmbedRequest(BaseModel):
    text: str = Field(min_length=1, max_length=20000)


class EmbedResponse(BaseModel):
    embedding: List[float]
    dim: int


class IngestRequest(BaseModel):
    texts: List[str] = Field(min_length=1, max_length=200)


class IngestResponse(BaseModel):
    task_ids: List[str]


def _embed(text: str, dim: int) -> List[float]:
    digest = hashlib.sha256(text.encode("utf-8")).digest()
    values = [b / 255.0 for b in digest]
    if dim <= len(values):
        return values[:dim]
    repeats = (dim + len(values) - 1) // len(values)
    padded = (values * repeats)[:dim]
    return padded


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/embed", response_model=EmbedResponse)
def embed(req: EmbedRequest) -> EmbedResponse:
    embedding = _embed(req.text, EMBEDDINGS_DIM)
    return EmbedResponse(embedding=embedding, dim=len(embedding))


@app.post("/ingest", response_model=IngestResponse)
def ingest(req: IngestRequest) -> IngestResponse:
    task_ids: List[str] = []
    for text in req.texts:
        if not text:
            continue
        result = celery_app.send_task("worker.process_text", args=[text])
        task_ids.append(result.id)
    return IngestResponse(task_ids=task_ids)
