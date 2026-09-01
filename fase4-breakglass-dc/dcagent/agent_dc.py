"""
TFM DC Agent — ejecución controlada de scripts de respuesta en un DC W2025.

Endurecimientos respecto a la versión inicial:
  - Ruta de scripts anclada y validada contra path traversal.
  - Comparación de token en tiempo constante.
  - Firma HMAC-SHA256 + ventana temporal + nonce anti-replay (por bandera).
  - Validación estricta del parámetro 'target' (argument injection en Windows).
  - Mapeo de parámetros por script.
  - PowerShell con -NoProfile -NonInteractive.
  - Saneado y truncado de stdout antes de devolverlo al orquestador.
  - Logging a fichero, consumible por el agente Wazuh del DC.
"""

import hashlib
import hmac
import json
import logging
import os
import re
import secrets
import subprocess
import time
from logging.handlers import RotatingFileHandler
from pathlib import Path

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

# --------------------------------------------------------------------------
# Configuración
# --------------------------------------------------------------------------
VALID_TOKEN = os.environ.get("AGENT_TOKEN", "")
HMAC_SECRET = os.environ.get("AGENT_HMAC_SECRET", "").encode()
REQUIRE_HMAC = os.environ.get("AGENT_REQUIRE_HMAC", "false").lower() == "true"

SCRIPTS_DIR = Path(os.environ.get("TFM_SCRIPTS_DIR", r"C:\tfm-scripts")).resolve()
LOG_PATH = Path(os.environ.get("TFM_LOG_PATH", r"C:\tfm-dc-agent\logs\agent.log"))

MAX_SKEW = 300          # segundos de tolerancia para el timestamp
MAX_STDOUT = 8000       # caracteres devueltos al orquestador
EXEC_TIMEOUT = 60

ALLOWED_SCRIPTS = [
    "disable_account.ps1",
    "enable_account.ps1",
    "collect_logs.ps1",
    "isolate_host.ps1",
    "reset_password.ps1",
    "rustdesk_enable.ps1",
    "rustdesk_disable.ps1",
]

# rustdesk_disable.ps1 no acepta parámetros; rustdesk_enable.ps1 usa TTLMinutes.
SCRIPT_PARAMS = {
    "rustdesk_enable.ps1": "ttl",
    "rustdesk_disable.ps1": None,
}  # el resto usa "target"

TARGET_RE = re.compile(r"^[A-Za-z0-9._\-\\]{1,64}$")
CONTROL_CHARS_RE = re.compile(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]")

# --------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------
LOG_PATH.parent.mkdir(parents=True, exist_ok=True)
logger = logging.getLogger("tfm-dc-agent")
logger.setLevel(logging.INFO)
_handler = RotatingFileHandler(LOG_PATH, maxBytes=10_485_760, backupCount=5,
                               encoding="utf-8")
_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
logger.addHandler(_handler)
logger.addHandler(logging.StreamHandler())

app = FastAPI(title="TFM DC Agent", version="2.0")
security = HTTPBearer()

_seen_nonces: dict[str, float] = {}


# --------------------------------------------------------------------------
# Autenticación
# --------------------------------------------------------------------------
def verify_token(creds: HTTPAuthorizationCredentials = Depends(security)) -> None:
    if not VALID_TOKEN:
        logger.error("AGENT_TOKEN no configurado")
        raise HTTPException(status_code=500, detail="AGENT_TOKEN not set")
    if not secrets.compare_digest(creds.credentials, VALID_TOKEN):
        logger.warning("Token invalido")
        raise HTTPException(status_code=403, detail="Forbidden")


async def verify_signature(request: Request, body: bytes) -> None:
    """HMAC-SHA256 sobre timestamp.nonce.body, coherente con la Fase 2."""
    if not REQUIRE_HMAC:
        return
    if not HMAC_SECRET:
        logger.error("AGENT_HMAC_SECRET no configurado con HMAC obligatorio")
        raise HTTPException(status_code=500, detail="HMAC secret not set")

    ts = request.headers.get("x-timestamp", "")
    nonce = request.headers.get("x-nonce", "")
    sig = request.headers.get("x-signature", "")
    if not (ts and nonce and sig):
        raise HTTPException(status_code=400, detail="Missing signature headers")

    try:
        skew = abs(time.time() - float(ts))
    except ValueError:
        raise HTTPException(status_code=400, detail="Bad timestamp")
    if skew > MAX_SKEW:
        logger.warning("Timestamp fuera de ventana: %.0fs", skew)
        raise HTTPException(status_code=400, detail="Timestamp outside window")

    now = time.time()
    for key, seen_at in list(_seen_nonces.items()):
        if now - seen_at > MAX_SKEW:
            del _seen_nonces[key]
    if nonce in _seen_nonces:
        logger.warning("Replay detectado, nonce=%s", nonce)
        raise HTTPException(status_code=409, detail="Replay detected")
    _seen_nonces[nonce] = now

    expected = hmac.new(HMAC_SECRET, f"{ts}.{nonce}.".encode() + body,
                        hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, sig):
        logger.warning("Firma HMAC invalida")
        raise HTTPException(status_code=403, detail="Bad signature")


# --------------------------------------------------------------------------
# Saneado de salida
# --------------------------------------------------------------------------
def sanitize_output(text: str) -> tuple[str, bool]:
    """
    stdout puede contener datos controlados por un atacante: collect_logs.ps1
    lee el campo Message del log de seguridad de Windows. Ese texto viaja
    DC -> orquestador -> motor de triaje, así que es una superficie de
    inyección indirecta por el canal de respuesta.
    """
    if not text:
        return "", False
    cleaned = CONTROL_CHARS_RE.sub("", text)
    truncated = len(cleaned) > MAX_STDOUT
    return cleaned[:MAX_STDOUT], truncated


# --------------------------------------------------------------------------
# Endpoints
# --------------------------------------------------------------------------
@app.post("/run")
async def run_script(request: Request, _=Depends(verify_token)):
    body = await request.body()
    await verify_signature(request, body)

    try:
        payload = json.loads(body or b"{}")
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid JSON")
    if not isinstance(payload, dict):
        raise HTTPException(status_code=400, detail="Invalid payload")

    script = payload.get("script", "")
    target = payload.get("target", "")
    ttl = payload.get("ttl_minutes", 30)

    if script not in ALLOWED_SCRIPTS:
        logger.warning("Script rechazado: %r", script)
        raise HTTPException(status_code=400, detail=f"Script no permitido: {script}")

    # Anclaje de ruta: la allowlist valida el nombre, esto valida la ubicación.
    script_path = (SCRIPTS_DIR / script).resolve()
    if script_path.parent != SCRIPTS_DIR or not script_path.is_file():
        logger.error("Ruta de script invalida: %s", script_path)
        raise HTTPException(status_code=400, detail="Script path invalid")

    param_kind = SCRIPT_PARAMS.get(script, "target")
    args: list[str] = []
    if param_kind == "target":
        if target and not TARGET_RE.fullmatch(str(target)):
            logger.warning("Target invalido: %r", target)
            raise HTTPException(status_code=400, detail="Invalid target")
        args = ["-target", str(target)]
    elif param_kind == "ttl":
        if not isinstance(ttl, int) or not 1 <= ttl <= 480:
            raise HTTPException(status_code=400, detail="Invalid ttl_minutes")
        args = ["-TTLMinutes", str(ttl)]

    logger.info("EJECUCION script=%s target=%s args=%s", script, target, args)

    try:
        result = subprocess.run(
            ["powershell.exe", "-NoProfile", "-NonInteractive",
             "-ExecutionPolicy", "Bypass", "-File", str(script_path), *args],
            capture_output=True, text=True, timeout=EXEC_TIMEOUT,
        )
    except subprocess.TimeoutExpired:
        logger.error("TIMEOUT script=%s", script)
        raise HTTPException(status_code=504, detail="Script timeout")

    stdout, truncated = sanitize_output(result.stdout)
    stderr, _ = sanitize_output(result.stderr)
    logger.info("RESULTADO script=%s returncode=%s", script, result.returncode)

    return {
        "script": script,
        "target": target,
        "stdout": stdout,
        "stderr": stderr,
        "returncode": result.returncode,
        "truncated": truncated,
    }


@app.get("/health")
async def health():
    return {
        "status": "ok",
        "agent": "dc01-tfm",
        "version": "2.0",
        "hmac_required": REQUIRE_HMAC,
        "token_configured": bool(VALID_TOKEN),
        "scripts_dir": str(SCRIPTS_DIR),
    }
