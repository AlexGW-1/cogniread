from fastapi import FastAPI
from pydantic import BaseModel
import os
from datetime import datetime

app = FastAPI(title="CogniRead AI", version="0.1.0")

@app.get("/health")
def health():
    return {"ok": True, "service": "ai", "ts": datetime.utcnow().isoformat() + "Z"}

class SummarizeIn(BaseModel):
    text: str

class ExplainIn(BaseModel):
    quote: str
    context: str | None = None

@app.post("/summarize")
def summarize(payload: SummarizeIn):
    # TODO: replace with LangChain chain
    text = payload.text.strip()
    return {
        "summary": (text[:240] + "…") if len(text) > 240 else text,
        "note": "stub (wire LLM later)"
    }

@app.post("/explain")
def explain(payload: ExplainIn):
    # TODO: replace with RAG + LLM
    return {
        "explanation": f"Stub explanation for: {payload.quote[:200]}",
        "note": "stub (wire retrieval + LLM later)"
    }

@app.post("/embed")
def embed(payload: SummarizeIn):
    # TODO: call embeddings model
    fake = [0.0] * 16
    return {"embedding": fake, "dim": len(fake), "note": "stub"}
