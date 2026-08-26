"""Configuracion del servicio de triage.

El motor de analisis se selecciona con la variable de entorno TRIAGE_MODE:

    deterministic  Motor de reglas puro. Reproducible y auditable. Por defecto.
    llm            Mistral 7B via Ollama, dentro del grafo LangGraph.
    hybrid         El LLM redacta resumen y recomendacion; el motor determinista
                   fija severidad y flags de respuesta. Degrada a determinista
                   si el LLM falla, agota el timeout o devuelve un esquema invalido.

Cambiar de modo no requiere tocar el workflow de n8n: el contrato de /triage
es identico en los tres casos.
"""

from __future__ import annotations

import os

MODE_DETERMINISTIC = "deterministic"
MODE_LLM = "llm"
MODE_HYBRID = "hybrid"
# Numero de hilos de inferencia. Determinado experimentalmente sobre esta VM
# (16 vCPU, 1 socket): la curva tiene su maximo en 8. Por encima, el coste de
# sincronizacion entre hilos supera la ganancia de paralelismo — con 16 hilos
# el rendimiento cae a un tercio.
OLLAMA_NUM_THREAD: int = int(os.getenv("OLLAMA_NUM_THREAD", "8"))

VALID_MODES = {MODE_DETERMINISTIC, MODE_LLM, MODE_HYBRID}


def _clean(value: str | None, default: str) -> str:
    return (value or default).strip().lower()


TRIAGE_MODE: str = _clean(os.getenv("TRIAGE_MODE"), MODE_DETERMINISTIC)
if TRIAGE_MODE not in VALID_MODES:
    TRIAGE_MODE = MODE_DETERMINISTIC

OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://ollama:11434").strip()
OLLAMA_MODEL: str = os.getenv("OLLAMA_MODEL", "mistral:7b").strip()

# Timeout duro para la inferencia. Un LLM colgado no debe bloquear la
# notificacion de un incidente: agotado el plazo se cae a determinista.
OLLAMA_TIMEOUT_SECONDS: int = int(os.getenv("OLLAMA_TIMEOUT_SECONDS", "45"))

# Temperatura baja: el triage no es una tarea creativa.
OLLAMA_TEMPERATURE: float = float(os.getenv("OLLAMA_TEMPERATURE", "0.1"))

# Distancia maxima tolerada, en niveles de severidad, entre el veredicto del LLM
# y el del motor determinista. Si el LLM rebaja la severidad mas de este margen
# se descarta su veredicto y se registra el hecho. Ver guardrails en tools.py.
MAX_SEVERITY_DOWNGRADE: int = int(os.getenv("MAX_SEVERITY_DOWNGRADE", "1"))
