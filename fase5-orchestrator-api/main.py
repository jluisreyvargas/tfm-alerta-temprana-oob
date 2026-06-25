from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from datetime import datetime, timezone
from minio import Minio
from minio.error import S3Error
import hashlib
import json
import io
import os

app = FastAPI(title="TFM OOB Orchestrator", version="0.2.0")

MINIO_ENDPOINT = os.getenv("MINIO_ENDPOINT", "minio:9000")
MINIO_ACCESS_KEY = os.getenv("MINIO_ACCESS_KEY", "minioadmin")
MINIO_SECRET_KEY = os.getenv("MINIO_SECRET_KEY", "minioadmin123")
MINIO_BUCKET = os.getenv("MINIO_BUCKET", "evidence")
MINIO_SECURE = os.getenv("MINIO_SECURE", "false").lower() == "true"

client = Minio(
    MINIO_ENDPOINT,
    access_key=MINIO_ACCESS_KEY,
    secret_key=MINIO_SECRET_KEY,
    secure=MINIO_SECURE,
)

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
    incidentid: str
    host: str
    profile: str
    source: str | None = None

@app.get("/health")
def health():
    return {"status": "ok"}

@app.post("/velociraptor/collect")
async def collect(req: CollectRequest):
    if req.profile not in ALLOWED:
        raise HTTPException(status_code=400, detail="Profile not allowed")

    ts = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    zip_sha256 = hashlib.sha256(f"{req.incidentid}{req.host}{ts}".encode()).hexdigest()

    manifest = {
        "incident_id": req.incidentid,
        "host": req.host,
        "collection_profile": req.profile,
        "selected_by": "forensics_agent_v1",
        "started_at": ts,
        "ended_at": ts,
        "artifact_list": ALLOWED[req.profile],
        "zip_path": f"s3://{MINIO_BUCKET}/{req.incidentid}/{req.host}/{ts}/velociraptor_collection.zip",
        "zip_sha256": zip_sha256,
        "operator": "orchestrator_v1",
        "source": req.source,
    }

    manifest_bytes = json.dumps(manifest, indent=2).encode("utf-8")
    sha_bytes = f"{zip_sha256}\n".encode("utf-8")

    manifest_object = f"{req.incidentid}/{req.host}/{ts}/manifest.json"
    sha_object = f"{req.incidentid}/{req.host}/{ts}/sha256.txt"

    try:
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

    return {
        "status": "queued",
        "velociraptorjobid": f"vr-{ts}",
        "manifest": manifest,
        "stored_objects": {
            "manifest": f"s3://{MINIO_BUCKET}/{manifest_object}",
            "sha256": f"s3://{MINIO_BUCKET}/{sha_object}"
        }
    }