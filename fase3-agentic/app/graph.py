"""Grafo LangGraph de triage.

El grafo se compila una sola vez al importar el modulo: recompilarlo en cada
peticion, como hacia la version anterior, anadia latencia por alerta sin aportar
nada, ya que la topologia es estatica.
"""

from __future__ import annotations

from typing import Any

from langgraph.graph import END, StateGraph

from app.agents import remediation_agent, triage_agent


def _build_graph():
    workflow = StateGraph(dict)
    workflow.add_node("triage_agent", triage_agent)
    workflow.add_node("remediation_agent", remediation_agent)
    workflow.set_entry_point("triage_agent")
    workflow.add_edge("triage_agent", "remediation_agent")
    workflow.add_edge("remediation_agent", END)
    return workflow.compile()


GRAPH = _build_graph()


def run_graph(payload: dict[str, Any]) -> dict[str, Any]:
    return GRAPH.invoke(
        {
            "wazuh": payload.get("wazuh", {}) or {},
            "cti": payload.get("cti", {}) or {},
            "decision": {},
            "messages": [],
        }
    )
