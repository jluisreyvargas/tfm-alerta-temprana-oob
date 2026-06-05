from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import subprocess, os

app = FastAPI(title="TFM DC Agent")
security = HTTPBearer()
VALID_TOKEN = os.environ["AGENT_TOKEN"]

ALLOWED_SCRIPTS = [
    "disable_account.ps1",
    "collect_logs.ps1",
    "isolate_host.ps1",
    "reset_password.ps1"
]

def verify_token(creds: HTTPAuthorizationCredentials = Depends(security)):
    if creds.credentials != VALID_TOKEN:
        raise HTTPException(status_code=403, detail="Forbidden")

@app.post("/run")
async def run_script(payload: dict, _=Depends(verify_token)):
    script = payload.get("script")
    target = payload.get("target", "")
    if script not in ALLOWED_SCRIPTS:
        raise HTTPException(status_code=400, detail="Script not allowed")
    result = subprocess.run(
        ["powershell.exe", "-File", f"C:\\tfm-scripts\\{script}", "-target", target],
        capture_output=True, text=True, timeout=60
    )
    return {
        "script": script,
        "target": target,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "returncode": result.returncode
    }

@app.get("/health")
async def health():
    return {"status": "ok"}