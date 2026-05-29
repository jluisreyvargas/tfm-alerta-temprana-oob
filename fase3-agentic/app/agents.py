from __future__ import annotations
from typing import Any
from app.tools import tool_score_incident, tool_map_mitre, tool_generate_response_flags, tool_format_cti_summary


def triage_agent(state: dict[str, Any]) -> dict[str, Any]:
    wazuh = state["wazuh"]
    cti = state["cti"]
    score = tool_score_incident(wazuh, cti)
    mitre = tool_map_mitre(wazuh, cti)
    state["decision"] = {
        **state.get("decision", {}),
        "severity_real": score["severity_real"],
        "mitre_tactic": mitre["mitre_tactic"],
        "mitre_technique": mitre["mitre_technique"],
        "summary": score["summary"],
        "cti_summary": tool_format_cti_summary(cti),
    }
    state.setdefault("messages", []).append({"agent": "triage_agent", "status": "done"})
    return state


def remediation_agent(state: dict[str, Any]) -> dict[str, Any]:
    decision = state["decision"]
    flags = tool_generate_response_flags(state["wazuh"], state["cti"], decision)
    state["decision"] = {
        **decision,
        "recommendation": flags["recommendation"],
        "requires_block": flags["requires_block"],
        "create_war_room": flags["create_war_room"],
    }
    state.setdefault("messages", []).append({"agent": "remediation_agent", "status": "done"})
    return state
