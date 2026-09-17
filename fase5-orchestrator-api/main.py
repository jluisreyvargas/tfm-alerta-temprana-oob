from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, Field, ValidationError
from datetime import datetime, timezone
from minio import Minio
from minio.error import S3Error
import hashlib
import hmac
import json
import io
import logging
import os
import sys
import time

sys.path.append("/app/shared")
from metrics_client import log_event

import velociraptor_client as vrc

logger = logging.getLogger(__name__)

app = FastAPI(title="TFM OOB Orchestrator", version="0.3.0")

MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "minio:9000")
MINIO_ACCESS_KEY = os.environ["MINIO_ACCESS_KEY"]
MINIO_SECRET_KEY = os.environ["MINIO_SECRET_KEY"]
MINIO_BUCKET = os.getenv("MINIO_BUCKET", "evidence")
MINIO_SECURE = os.getenv("MINIO_SECURE", "false").lower() == "true"

client = Minio(
    MINIO_ENDPOINT,
    access_key=MINIO_ACCESS_KEY,
    secret_key=MINIO_SECRET_KEY,
    secure=MINIO_SECURE,
)

# --------------------------------------------------------------------------
# Autenticacion HMAC (P0-4, Fase B)
#
# Replica el patron de fase4-breakglass-dc/dcagent/agent_dc.py: HMAC-SHA256
# sobre "{ts}.{nonce}." + cuerpo crudo, ventana temporal y cache anti-replay.
#
# A diferencia de la Fase 4c (AGENT_REQUIRE_HMAC por defecto false, porque
# migraba desde Bearer con un parque en produccion y necesitaba fase de
# transicion), aqui el default es true: no hay consumidores activos, no hay
# migracion que justificar, y un interruptor cuyo valor por defecto desactiva
# el control es la misma clase de fallo que un valor por defecto inseguro.
# --------------------------------------------------------------------------
ORCH_REQUIRE_HMAC = os.environ.get("ORCH_REQUIRE_HMAC", "true").lower() == "true"

if ORCH_REQUIRE_HMAC:
    # Sin valor por defecto: si falta el secreto con HMAC obligatorio, el
    # proceso debe fallar de forma ruidosa al arrancar (KeyError), no aceptar
    # peticiones sin verificar.
    ORCH_HMAC_SECRET = os.environ["ORCH_HMAC_SECRET"].encode()
else:
    ORCH_HMAC_SECRET = os.environ.get("ORCH_HMAC_SECRET", "").encode()

MAX_SKEW = 300  # segundos de tolerancia para el timestamp (igual que la Fase 4c)

_seen_nonces: dict[str, float] = {}


async def verify_signature(request: Request, body: bytes) -> None:
    """HMAC-SHA256 sobre "{ts}.{nonce}." + body crudo, coherente con la Fase 4c.

    Orden de comprobaciones: cabeceras presentes -> timestamp parseable ->
    dentro de ventana -> purga de nonces -> nonce no visto -> firma correcta.
    La firma se comprueba en ultimo lugar: hacerlo antes que el anti-replay
    permitiria a un atacante distinguir nonces ya usados.
    """
    if not ORCH_REQUIRE_HMAC:
        return
    if not ORCH_HMAC_SECRET:
        logger.error("ORCH_HMAC_SECRET no configurado con HMAC obligatorio")
        raise HTTPException(status_code=500, detail="HMAC secret not set")

    ts = request.headers.get("x-timestamp", "")
    nonce = request.headers.get("x-nonce", "")
    sig = request.headers.get("x-signature", "")
    if not (ts and nonce and sig):
        logger.warning("Faltan cabeceras de firma")
        raise HTTPException(status_code=400, detail="Missing signature headers")

    try:
        skew = abs(time.time() - float(ts))
    except ValueError:
        logger.warning("Timestamp no parseable: %r", ts)
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

    expected = hmac.new(ORCH_HMAC_SECRET, f"{ts}.{nonce}.".encode() + body,
                        hashlib.sha256).hexdigest()
    if not hmac.compare_digest(expected, sig):
        logger.warning("Firma HMAC invalida")
        raise HTTPException(status_code=403, detail="Bad signature")


ALLOWED = {
    "credential_dump_collection": [
        "Windows.System.Pslist",
        "Windows.Memory.Acquisition"
    ],
    "ransomware_triage": [
        "Windows.System.Pslist"
    ],
    "lateral_movement_probe": [
        "Windows.Network.Netstat",
        "Windows.System.Pslist"
    ],
    "generic_high_signal_collection": [
        "Windows.System.Pslist"
    ],
}

class CollectRequest(BaseModel):
    # incidentid y host construyen la clave del objeto en MinIO
    # (f"{req.incidentid}/{req.host}/{ts}/manifest.json"). Sin validar, permiten
    # escribir en rutas arbitrarias del bucket y sobrescribir el manifiesto de
    # otro incidente. El usuario tfm-orchestrator no puede borrar objetos
    # (politica evidence-writer, sin s3:DeleteObject) pero si sobrescribirlos,
    # comprobado experimentalmente en el P0-3.
    incidentid: str = Field(pattern=r"^[A-Za-z0-9._-]{1,64}$")
    host: str = Field(pattern=r"^[A-Za-z0-9._-]{1,64}$")
    profile: str
    # source es descriptivo, llega del payload y acaba en manifest.json (y, cuando
    # se conecte el consumidor, en el indice de metricas). No construye la clave
    # del objeto, asi que no es vector de traversal; pero es texto libre de un
    # payload externo, y se acota a la misma forma que los otros identificadores
    # para evitar inyeccion en almacen/indice y documentos sobredimensionados.
    # Sin consumidores activos, el coste de restringirlo ahora es nulo.
    source: str | None = Field(default=None, pattern=r"^[A-Za-z0-9._-]{1,64}$")

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/velociraptor/collect")
async def collect(request: Request):
    body = await request.body()
    # Verificar la firma antes de validar el modelo, para no exponer la logica
    # de validacion a peticiones no autenticadas.
    await verify_signature(request, body)

    try:
        req = CollectRequest.model_validate_json(body)
    except ValidationError as e:
        raise HTTPException(status_code=422, detail=json.loads(e.json()))

    if req.profile not in ALLOWED:
        raise HTTPException(status_code=400, detail="Profile not allowed")

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    # ----------------------------------------------------------------------
    # Recoleccion real por gRPC contra el cliente Velociraptor del host.
    #
    # ALLOWED[req.profile] es la lista blanca aplicada AQUI, en el orchestrator:
    # es el control de seguridad principal ahora que el orchestrator tiene
    # credencial para lanzar artefactos en la flota. Nunca se pasa a
    # Velociraptor un artefacto que no este en esta lista, venga de donde venga
    # el payload.
    #
    # Hasta la Fase 5_4b este bloque no existia: zip_sha256 era el hash de
    # incidentid+host+ts, el ZIP declarado no existia en ningun bucket y
    # started_at == ended_at en todos los manifiestos.
    # ----------------------------------------------------------------------
    try:
        result = vrc.collect(req.host, ALLOWED[req.profile])
    except vrc.NoClientError:
        raise HTTPException(
            status_code=404,
            detail=f"No hay cliente Velociraptor para host '{req.host}'")
    except vrc.CollectionTimeout as e:
        # La coleccion se lanzo pero no termino dentro del timeout. No se
        # escribe manifiesto: no hay ZIP que referenciar todavia. Se devuelve
        # el flow_id para poder recuperarla, en vez de perderla en silencio.
        raise HTTPException(
            status_code=504,
            detail={"status": "timeout", "flow_id": e.flow_id,
                    "client_id": e.client_id,
                    "message": "Coleccion lanzada, no terminada en el timeout"})
    except vrc.CollectionError as e:
        raise HTTPException(status_code=502, detail=f"Error de coleccion: {e}")

    # Hash sobre los bytes reales del ZIP en el volumen compartido, en
    # streaming para no cargar en memoria una adquisicion grande.
    h = hashlib.sha256()
    zip_size = 0
    with open(result["zip_local_path"], "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
            zip_size += len(chunk)
    zip_sha256 = h.hexdigest()

    started_iso = datetime.fromtimestamp(
        result["started_at"], timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    ended_iso = datetime.fromtimestamp(
        result["ended_at"], timezone.utc).strftime("%Y%m%dT%H%M%SZ")

    zip_object = f"{req.incidentid}/{req.host}/{ts}/velociraptor_collection.zip"

    manifest = {
        "incident_id": req.incidentid,
        "host": req.host,
        "collection_profile": req.profile,
        "selected_by": "forensics_agent_v1",
        "started_at": started_iso,
        "ended_at": ended_iso,
        "artifact_list": ALLOWED[req.profile],
        "velociraptor_client_id": result["client_id"],
        "velociraptor_client_os": result["client_os"],
        "velociraptor_flow_id": result["flow_id"],
        "total_collected_rows": result["total_rows"],
        "zip_path": f"s3://{MINIO_BUCKET}/{zip_object}",
        "zip_size_bytes": zip_size,
        "zip_sha256": zip_sha256,
        "operator": "orchestrator_v1",
        "source": req.source,
    }

    manifest_bytes = json.dumps(manifest, indent=2).encode("utf-8")
    # Formato compatible con `sha256sum -c`: un tercero puede descargar el ZIP
    # y este fichero a un directorio y verificar la integridad con un comando
    # estandar, fuera del workflow.
    sha_bytes = f"{zip_sha256}  velociraptor_collection.zip\n".encode("utf-8")

    manifest_object = f"{req.incidentid}/{req.host}/{ts}/manifest.json"
    sha_object = f"{req.incidentid}/{req.host}/{ts}/sha256.txt"

    write_start = time.monotonic()
    try:
        # El ZIP primero: es la evidencia, y el manifiesto la referencia. Si
        # fallara la subida del ZIP, no debe quedar un manifiesto apuntando a
        # un objeto inexistente.
        with open(result["zip_local_path"], "rb") as fh:
            client.put_object(
                MINIO_BUCKET,
                zip_object,
                data=fh,
                length=zip_size,
                content_type="application/zip",
            )

        client.put_object(
            MINIO_BUCKET,
            manifest_object,
            data=io.BytesIO(manifest_bytes),
            length=len(manifest_bytes),
            content_type="application/json",
        )

        client.put_object(
            MINIO_BUCKET,
            sha_object,
            data=io.BytesIO(sha_bytes),
            length=len(sha_bytes),
            content_type="text/plain",
        )

    except S3Error as e:
        raise HTTPException(status_code=500, detail=f"MinIO error: {str(e)}")

    duration_ms = int((time.monotonic() - write_start) * 1000)

    # La evidencia ya esta persistida en MinIO. Un fallo de telemetria no debe
    # convertir una coleccion correcta en un 500: eso provocaria reintentos de
    # n8n y evidencia duplicada. Ocurrio durante la remediacion del P0-3.
    try:
        log_event(
            "collection_completed",
            incident_id=req.incidentid,
            host=req.host,
            profile=req.profile,
            collection_id=result["flow_id"],
            minio_path=f"s3://{MINIO_BUCKET}/{manifest_object}",
            duration_ms=duration_ms,
            source="orchestrator",
        )
    except Exception as e:
        logger.warning("no se pudo registrar la metrica collection_completed: %s", e)

    return {
        "status": "completed",
        "velociraptorjobid": result["flow_id"],
        "manifest": manifest,
        "stored_objects": {
            "zip": f"s3://{MINIO_BUCKET}/{zip_object}",
            "manifest": f"s3://{MINIO_BUCKET}/{manifest_object}",
            "sha256": f"s3://{MINIO_BUCKET}/{sha_object}"
        }
    }