from __future__ import annotations
from langgraph.graph import StateGraph, END
from app.agents import triage_agent, remediation_agent


def run_graph(payload: dict):
    workflow = StateGraph(dict)
    workflow.add_node("triage_agent", triage_agent)
    workflow.add_node("remediation_agent", remediation_agent)
    workflow.set_entry_point("triage_agent")
    workflow.add_edge("triage_agent", "remediation_agent")
    workflow.add_edge("remediation_agent", END)
    graph = workflow.compile()
    return graph.invoke({"wazuh": payload.get("wazuh", {}), "cti": payload.get("cti", {}), "decision": {}, "messages": []})
