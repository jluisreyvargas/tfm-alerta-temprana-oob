"""Servicio HTTP del motor de triage.

Contrato estable frente a n8n: POST /triage devuelve siempre {wazuh, cti,
decision, messages}, con independencia del motor configurado en TRIAGE_MODE.
"""

from __future__ import annotations

import logging
import sys

from fastapi import FastAPI

from app.config import OLLAMA_MODEL, TRIAGE_MODE
from app.graph import run_graph
from app.models import TriageRequest

sys.path.append("/app/shared")

logger = logging.getLogger("triage")
logging.basicConfig(level=logging.INFO)

try:
    from metrics_client import log_event
except ImportError:  # El volumen de Fase 7 puede no estar montado.
    def log_event(*args, **kwargs):  # type: ignore[misc]
        logger.debug("metrics_client no disponible; evento descartado.")

app = FastAPI(title="TFM - Motor de triage OOB")


@app.get("/health")
def health() -> dict[str, str]:
    return {
        "status": "ok",
        "triage_mode": TRIAGE_MODE,
        "llm_model": OLLAMA_MODEL,
    }


@app.post("/triage")
def triage(payload: TriageRequest) -> dict:
    result = run_graph(payload.model_dump())
    decision = result.get("decision", {})
    wazuh = result.get("wazuh", {})

    if decision.get("guardrail_triggered"):
        logger.warning(
            "Guardrail activado para la regla %s: %s",
            wazuh.get("rule_id", "?"),
            decision.get("guardrail_reason", ""),
        )
    if decision.get("degraded_reason"):
        logger.warning("Degradacion de motor: %s", decision["degraded_reason"])

    # La telemetria de Fase 7 no puede tumbar la ruta de incidente. Si el
    # indexador esta caido, si la credencial ha rotado o si el volumen no esta
    # montado, se pierde la metrica y se entrega el veredicto igualmente: un
    # incidente no notificado es un fallo mucho mas grave que una metrica
    # ausente. Es el mismo principio de degradacion que aplica el grafo cuando
    # el LLM no responde. El except amplio es deliberado: metrics_client
    # puede fallar por red, TLS, autenticacion o serializacion, y ninguna de
    # esas causas debe propagarse hasta el 500 de /triage.
    try:
        log_event(
            "triage_decision",
            incident_id=wazuh.get("alert_id") or wazuh.get("rule_id") or "unknown",
            host=wazuh.get("agent_name") or "unknown",
            profile=decision.get("recommendation", "unknown"),
            decision=decision.get("severity_real", "unknown"),
            source=f"langgraph-agent[{decision.get('analysis_mode', 'unknown')}]",
        )
    except Exception as exc:  # noqa: BLE001 - deliberadamente amplio
        logger.warning("No se pudo registrar la metrica de triage: %s", exc)

    return result