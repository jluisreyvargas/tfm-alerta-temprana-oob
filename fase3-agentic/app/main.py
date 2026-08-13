import sys
sys.path.append("/app/shared")

from fastapi import FastAPI
from app.graph import run_graph
from app.models import TriageRequest
from metrics_client import log_event

app = FastAPI(title="TFM LangGraph Agent Service")

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/triage")
def triage(payload: TriageRequest):
    result = run_graph(payload.model_dump())

    decision = result.get("decision", {}) if isinstance(result, dict) else {}
    wazuh = result.get("wazuh", {}) if isinstance(result, dict) else {}

    log_event(
        "triage_decision",
        incident_id=wazuh.get("incident_id") or wazuh.get("id") or "unknown",
        host=wazuh.get("host") or wazuh.get("agent_name") or "unknown",
        profile=decision.get("recommendation", "unknown"),
        decision=decision.get("severity_real", "unknown"),
        source="langgraph-agent",
    )

    return result