import json
import os
import ssl
import base64
import urllib.request
from datetime import datetime, timezone

OS_URL = os.getenv("OS_URL", "https://single-node-wazuh.indexer-1:9200")
OS_USER = os.getenv("OS_USER", "admin")
OS_PASS = os.getenv("OS_PASS", "SecretPassword")
INDEX = os.getenv("OS_INDEX", "tfm-metrics-events")

_ctx = ssl.create_default_context()
_ctx.check_hostname = False
_ctx.verify_mode = ssl.CERT_NONE


def log_event(event_type: str, **fields):
    """
    Envia un evento de metrica a OpenSearch (indice tfm-metrics-events).
    No lanza excepcion si falla, para no bloquear el flujo principal.
    Usa solo librerias estandar de Python (sin dependencia de 'requests').
    """
    doc = {
        "@timestamp": datetime.now(timezone.utc).isoformat(),
        "event_type": event_type,
        "source": fields.pop("source", "unknown"),
        **fields,
    }

    body = json.dumps(doc).encode("utf-8")
    auth = base64.b64encode(f"{OS_USER}:{OS_PASS}".encode()).decode()

    req = urllib.request.Request(
        f"{OS_URL}/{INDEX}/_doc",
        data=body,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Basic {auth}",
        },
    )

    try:
        with urllib.request.urlopen(req, context=_ctx, timeout=3) as resp:
            return json.loads(resp.read().decode())
    except Exception as e:
        print(f"[metrics_client] WARN: no se pudo indexar evento {event_type}: {e}")
        return None
