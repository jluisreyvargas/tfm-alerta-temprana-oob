from fastapi import FastAPI
from app.graph import run_graph
from app.models import TriageRequest

app = FastAPI(title="TFM LangGraph Agent Service")

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/triage")
def triage(payload: TriageRequest):
    return run_graph(payload.model_dump())
