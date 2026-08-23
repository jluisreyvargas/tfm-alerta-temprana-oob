"""Nodos del grafo LangGraph.

triage_agent      Determina severidad, atribucion ATT&CK y resumen.
remediation_agent Deriva las acciones sugeridas a partir de esa decision.

El motor efectivo se decide en tiempo de ejecucion segun TRIAGE_MODE, y queda
registrado en decision["analysis_mode"]. Ese campo es el que renderiza el
mensaje de Rocket.Chat: el informe no puede atribuir a un modelo un veredicto
que produjo el motor de reglas.
"""

from __future__ import annotations

from typing import Any

from app.config import MODE_DETERMINISTIC, MODE_HYBRID, MODE_LLM, TRIAGE_MODE
from app.llm import LLMUnavailable, run_llm_triage
from app.tools import (
    apply_severity_guardrail,
    tool_format_cti_summary,
    tool_generate_response_flags,
    tool_map_mitre,
    tool_score_incident,
)


def _note(state: dict[str, Any], agent: str, detail: str) -> None:
    state.setdefault("messages", []).append({"agent": agent, "detail": detail})


def triage_agent(state: dict[str, Any]) -> dict[str, Any]:
    wazuh: dict[str, Any] = state.get("wazuh", {})
    cti: dict[str, Any] = state.get("cti", {})

    baseline = tool_score_incident(wazuh, cti)
    mitre = tool_map_mitre(wazuh)
    cti_summary = tool_format_cti_summary(cti)

    decision: dict[str, Any] = {
        "severity_real": baseline["severity_real"],
        "summary": baseline["summary"],
        "score": baseline["score"],
        "score_breakdown": baseline["score_breakdown"],
        "mitre_tactic": mitre["mitre_tactic"],
        "mitre_technique": mitre["mitre_technique"],
        "mitre_source": mitre["mitre_source"],
        "cti_summary": cti_summary,
        "analysis_mode": MODE_DETERMINISTIC,
        "guardrail_triggered": False,
        "guardrail_reason": "",
        "degraded_reason": "",
    }

    if TRIAGE_MODE == MODE_DETERMINISTIC:
        _note(state, "triage_agent", "Motor determinista.")
        state["decision"] = decision
        return state

    try:
        verdict = run_llm_triage(wazuh, cti_summary, mitre)
    except LLMUnavailable as exc:
        decision["analysis_mode"] = f"{MODE_DETERMINISTIC} (degradado desde {TRIAGE_MODE})"
        decision["degraded_reason"] = str(exc)
        _note(state, "triage_agent", f"Degradacion a determinista: {exc}")
        state["decision"] = decision
        return state

    guardrail = apply_severity_guardrail(
        llm_severity=verdict["severity_real"],
        deterministic_severity=baseline["severity_real"],
    )

    decision["analysis_mode"] = TRIAGE_MODE
    decision["summary"] = verdict["summary"]
    decision["llm_recommendation"] = verdict["recommendation"]
    decision["guardrail_triggered"] = guardrail["guardrail_triggered"]
    decision["guardrail_reason"] = guardrail["guardrail_reason"]

    if TRIAGE_MODE == MODE_LLM:
        # El LLM manda sobre la severidad, sujeto al guardrail antidegradacion.
        decision["severity_real"] = guardrail["severity_real"]
    elif TRIAGE_MODE == MODE_HYBRID:
        # La severidad y los flags los fija el motor determinista; el LLM solo
        # aporta la redaccion. Se conserva su propuesta para poder compararlas.
        decision["severity_real"] = baseline["severity_real"]
        decision["llm_proposed_severity"] = verdict["severity_real"]

    _note(state, "triage_agent", f"Motor {TRIAGE_MODE}.")
    state["decision"] = decision
    return state


def remediation_agent(state: dict[str, Any]) -> dict[str, Any]:
    decision: dict[str, Any] = state.get("decision", {})
    flags = tool_generate_response_flags(
        state.get("wazuh", {}), state.get("cti", {}), decision
    )

    # En modo llm la recomendacion del modelo prevalece, salvo que el guardrail
    # haya invalidado su veredicto: en ese caso no es fiable ninguna de sus salidas.
    recommendation = flags["recommendation"]
    if (
        decision.get("analysis_mode") == MODE_LLM
        and not decision.get("guardrail_triggered")
        and decision.get("llm_recommendation")
    ):
        recommendation = decision["llm_recommendation"]

    state["decision"] = {
        **decision,
        "requires_block": flags["requires_block"],
        "create_war_room": flags["create_war_room"],
        "recommendation": recommendation,
    }
    _note(state, "remediation_agent", "Flags de respuesta generados.")
    return state
