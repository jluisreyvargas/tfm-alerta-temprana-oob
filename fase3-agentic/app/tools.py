"""Herramientas deterministas de triage.

Todas las funciones de este modulo son puras y sin efectos laterales, lo que
permite ejercitarlas con tests unitarios y hace el veredicto reproducible.
"""

from __future__ import annotations

from typing import Any

from app.config import MAX_SEVERITY_DOWNGRADE

# Escala ordinal de severidad. El indice permite comparar veredictos.
SEVERITY_SCALE: list[str] = ["BAJA", "MEDIA", "ALTA", "CRITICA"]

UNKNOWN = "no determinado"


def severity_rank(severity: str) -> int:
    """Devuelve la posicion ordinal de una severidad, o -1 si no es valida."""
    try:
        return SEVERITY_SCALE.index(str(severity).strip().upper())
    except ValueError:
        return -1


def _as_int(value: Any, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _first(value: Any) -> str:
    """Wazuh entrega rule.mitre.* como listas. Extrae el primer elemento."""
    if isinstance(value, (list, tuple)):
        return str(value[0]).strip() if value else ""
    if value is None:
        return ""
    return str(value).strip()


def tool_format_cti_summary(cti: dict[str, Any]) -> str:
    parts: list[str] = []
    if cti.get("enrichment_skipped"):
        return f"Enriquecimiento CTI omitido: {cti.get('enrichment_skipped')}"
    if cti.get("abuse_confidence") is not None:
        parts.append(f"AbuseIPDB confidence={cti['abuse_confidence']}")
    if cti.get("abuse_total_reports") is not None:
        parts.append(f"reportes={cti['abuse_total_reports']}")
    if cti.get("vt_malicious") is not None:
        parts.append(f"VirusTotal motores maliciosos={cti['vt_malicious']}")
    if cti.get("misp_total") is not None:
        parts.append(f"MISP coincidencias={cti['misp_total']}")
    return " | ".join(parts) if parts else "CTI sin datos relevantes"


def tool_score_incident(wazuh: dict[str, Any], cti: dict[str, Any]) -> dict[str, Any]:
    """Puntua el incidente sumando el nivel de Wazuh y las senales CTI.

    El desglose se devuelve explicitamente para que la decision sea auditable:
    en un TFM interesa poder justificar por que una alerta acabo en CRITICA.
    """
    level = _as_int(wazuh.get("rule_level"))
    abuse = _as_int(cti.get("abuse_confidence"))
    vt = _as_int(cti.get("vt_malicious"))
    misp = _as_int(cti.get("misp_total"))

    breakdown: dict[str, int] = {"nivel_wazuh": level}
    breakdown["abuseipdb"] = 2 if abuse > 50 else 0
    breakdown["virustotal"] = 2 if vt > 10 else 0
    breakdown["misp"] = 2 if misp > 0 else 0

    score = sum(breakdown.values())

    if score >= 12:
        severity = "CRITICA"
    elif score >= 9:
        severity = "ALTA"
    elif score >= 6:
        severity = "MEDIA"
    else:
        severity = "BAJA"

    justification = ", ".join(f"{k}={v}" for k, v in breakdown.items())
    return {
        "severity_real": severity,
        "score": score,
        "score_breakdown": breakdown,
        "summary": f"Severidad {severity} (score={score}: {justification}).",
    }


def tool_map_mitre(wazuh: dict[str, Any]) -> dict[str, str]:
    """Resuelve la atribucion ATT&CK con precedencia explicita.

    1. Mapeo nativo de Wazuh (rule.mitre). Es el dato autoritativo: lo mantiene
       el ruleset upstream y viene ya asociado a la regla que disparo.
    2. Heuristica local, solo para reglas sin mapeo nativo.
    3. "no determinado". Nunca se inventa una tecnica para una alerta que no
       se reconoce: una atribucion fabricada es peor que la ausencia de dato.
    """
    mitre_id = _first(wazuh.get("mitre_id"))
    mitre_tactic = _first(wazuh.get("mitre_tactic"))
    mitre_technique = _first(wazuh.get("mitre_technique"))

    if mitre_id or mitre_technique:
        technique = f"{mitre_id} - {mitre_technique}".strip(" -") or UNKNOWN
        return {
            "mitre_tactic": mitre_tactic or UNKNOWN,
            "mitre_technique": technique,
            "mitre_source": "wazuh_native",
        }

    desc = str(wazuh.get("rule_desc", "")).lower()
    groups = " ".join(str(g).lower() for g in (wazuh.get("rule_groups") or []))
    haystack = f"{desc} {groups}"

    heuristics: list[tuple[tuple[str, ...], str, str]] = [
        (
            (
                "auth failures",
                "ssh",
                "brute force",
                "authentication_failed",
                "authentication_failures",
                "invalid_login",
                "non-existent user",
                "invalid user",
            ),
            "TA0006 - Credential Access",
            "T1110 - Brute Force",
        ),
        (
            ("account enumeration", "user enumeration"),
            "TA0007 - Discovery",
            "T1087 - Account Discovery",
        ),
        (
            ("integrity checksum changed", "syscheck"),
            "TA0040 - Impact",
            "T1565.001 - Stored Data Manipulation",
        ),
    ]

    for needles, tactic, technique in heuristics:
        if any(n in haystack for n in needles):
            return {
                "mitre_tactic": tactic,
                "mitre_technique": technique,
                "mitre_source": "heuristic",
            }

    return {
        "mitre_tactic": UNKNOWN,
        "mitre_technique": UNKNOWN,
        "mitre_source": "unmapped",
    }


def tool_generate_response_flags(
    wazuh: dict[str, Any],
    cti: dict[str, Any],
    decision: dict[str, Any],
) -> dict[str, Any]:
    """Deriva las acciones sugeridas a partir de la severidad consolidada.

    El bloqueo solo se propone si ademas hay una IP publica sobre la que actuar:
    proponer bloquear una IP privada o ausente genera ruido operativo.
    """
    severity = str(decision.get("severity_real", "BAJA")).upper()
    escalated = severity in {"ALTA", "CRITICA"}

    src_ip = str(wazuh.get("src_ip") or "").strip()
    ip_actionable = bool(src_ip) and not cti.get("src_ip_is_private", False)

    requires_block = escalated and ip_actionable
    create_war_room = escalated

    if requires_block:
        recommendation = f"Bloquear {src_ip} en perimetro y abrir War Room del incidente."
    elif escalated:
        recommendation = "Abrir War Room y determinar el vector: sin IP publica sobre la que actuar."
    else:
        recommendation = "Monitorizar y correlacionar con contexto adicional."

    return {
        "requires_block": requires_block,
        "create_war_room": create_war_room,
        "recommendation": recommendation,
    }


def apply_severity_guardrail(
    llm_severity: str,
    deterministic_severity: str,
) -> dict[str, Any]:
    """Contencion frente a rebajas de severidad no justificadas.

    Los campos de la alerta que alimentan el prompt (rule_desc, full_log) pueden
    contener texto controlado por un atacante: un nombre de usuario en un fallo
    SSH acaba literalmente dentro del contexto del modelo. Una inyeccion indirecta
    de prompt buscaria justamente rebajar la severidad y desactivar el bloqueo.

    Se acepta la severidad del LLM solo si no rebaja la determinista mas de
    MAX_SEVERITY_DOWNGRADE niveles. Escalar siempre esta permitido.
    """
    llm_rank = severity_rank(llm_severity)
    det_rank = severity_rank(deterministic_severity)

    if llm_rank < 0:
        return {
            "severity_real": deterministic_severity,
            "guardrail_triggered": True,
            "guardrail_reason": f"El modelo devolvio una severidad no valida: {llm_severity!r}.",
        }

    downgrade = det_rank - llm_rank
    if downgrade > MAX_SEVERITY_DOWNGRADE:
        return {
            "severity_real": deterministic_severity,
            "guardrail_triggered": True,
            "guardrail_reason": (
                f"El modelo rebajo la severidad de {deterministic_severity} a "
                f"{llm_severity} ({downgrade} niveles). Se conserva la determinista."
            ),
        }

    return {
        "severity_real": SEVERITY_SCALE[llm_rank],
        "guardrail_triggered": False,
        "guardrail_reason": "",
    }
