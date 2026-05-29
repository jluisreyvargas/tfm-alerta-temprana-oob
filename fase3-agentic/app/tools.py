from __future__ import annotations
from typing import Any


def tool_format_cti_summary(cti: dict[str, Any]) -> str:
    parts = []
    if cti.get("abuse_confidence") is not None:
        parts.append(f"AbuseIPDB confidence={cti['abuse_confidence']}")
    if cti.get("abuse_total_reports") is not None:
        parts.append(f"reports={cti['abuse_total_reports']}")
    if cti.get("vt_malicious") is not None:
        parts.append(f"VirusTotal malicious={cti['vt_malicious']}")
    if cti.get("misp_total") is not None:
        parts.append(f"MISP matches={cti['misp_total']}")
    return " | ".join(parts) if parts else "CTI sin datos relevantes"


def tool_score_incident(wazuh: dict[str, Any], cti: dict[str, Any]) -> dict[str, Any]:
    level = int(wazuh.get("rule_level", 0) or 0)
    abuse = int(cti.get("abuse_confidence", 0) or 0)
    vt = int(cti.get("vt_malicious", 0) or 0)
    misp = int(cti.get("misp_total", 0) or 0)
    score = level + (2 if abuse > 50 else 0) + (2 if vt > 10 else 0) + (2 if misp > 0 else 0)
    if score >= 12:
        severity = "CRITICA"
    elif score >= 9:
        severity = "ALTA"
    elif score >= 6:
        severity = "MEDIA"
    else:
        severity = "BAJA"
    return {
        "severity_real": severity,
        "summary": f"Severidad calculada: {severity} (score={score})"
    }


def tool_map_mitre(wazuh: dict[str, Any], cti: dict[str, Any]) -> dict[str, str]:
    desc = str(wazuh.get("rule_desc", "")).lower()
    if "ssh brute force" in desc or "brute force" in desc:
        return {
            "mitre_tactic": "TA0006 - Credential Access",
            "mitre_technique": "T1110 - Brute Force"
        }
    return {
        "mitre_tactic": "TA0005 - Defense Evasion",
        "mitre_technique": "T1078 - Valid Accounts"
    }


def tool_generate_response_flags(wazuh: dict[str, Any], cti: dict[str, Any], decision: dict[str, Any]) -> dict[str, Any]:
    severity = decision.get("severity_real", "BAJA")
    requires_block = severity in {"ALTA", "CRITICA"}
    create_war_room = severity in {"ALTA", "CRITICA"}
    recommendation = (
        "Bloquear la IP y abrir War Room" if requires_block else "Monitorizar y correlacionar con más contexto"
    )
    return {
        "requires_block": requires_block,
        "create_war_room": create_war_room,
        "recommendation": recommendation,
    }
