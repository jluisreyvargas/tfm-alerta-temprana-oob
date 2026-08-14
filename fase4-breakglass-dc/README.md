# 🔗 Fase 4 · Break-Glass - RustDesk y Scripts DC

> [!NOTE]
> **🎯 Objetivo de la fase**  
> Implementar acceso remoto controlado y ejecución de scripts en DCs mediante RustDesk (break-glass SW) y Python Agents con Cloudflare Tunnels.

> [!TIP]
> Esta fase permite acción remota en endpoints/DCs cuando el entorno corporativo puede estar comprometido, usando túneles TLS salientes.

## 📋 Estado

- [x] 🐳 RustDesk Server en Docker enclave
- [x] 🔐 Active Response Wazuh para habilitar/deshabilitar RustDesk con TTL
- [x] 🤖 Python Agent Flask en W2025 DCs
- [x] 🌐 cloudflared como servicio Windows en cada DC
- [x] 📡 Endpoint POST `/run` con Bearer Token y allowlist de scripts
- [x] ✅ Flujo completo: aprobación → Orquestador → CF Tunnel → DC → callback → IRIS
- [ ] 📜 Scripts adicionales: `disableaccount.ps1`, `collectlogs.ps1`, `isolatehost.ps1`

## 🏗️ Arquitectura

```text
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Orquestador │────▶│  Cloudflare  │────▶│ Python Agent │
│   Aprobación │     │   Tunnels    │     │  localhost   │
└──────────────┘     └──────────────┘     └──────────────┘
                            │                     │
                     ┌──────▼──────┐       ┌──────▼──────┐
                     │  RustDesk   │       │  W2025 DC   │
                     │   Server    │       │  Scripts    │
                     └─────────────┘       └─────────────┘
```

## 🔧 Componentes

### 🖥️ RustDesk Server
- **Función:** Acceso remoto temporal break-glass
- **Puertos:** `21115-21116`, `21118-21119`
- **TTL:** 30 minutos por defecto

### 🌐 Cloudflare Tunnels
- **Función:** Túnel TLS seguro hacia agentes locales
- **Configuración:** `cloudflared` como servicio Windows
- **Hostname:** `agent-dc01.tudominio.com`

### 🤖 Python Agent
- **Función:** Ejecución de scripts con privilegios
- **Puerto:** `localhost:8000`
- **Auth:** Bearer Token + allowlist de scripts

## ⚙️ Configuración Aplicada

### cloudflared (config.yml)

```yaml
tunnel: <TUNNEL_UUID>
credentials-file: C:\agent\.cloudflared\<UUID>.json
ingress:
  - hostname: agent-dc01.tudominio.com
    service: http://localhost:8000
  - service: http_status:404
```

### Python Agent (agentdc.py)

```python
from fastapi import FastAPI, Depends, HTTPException
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import subprocess, os

app = FastAPI()
security = HTTPBearer()
VALID_TOKEN = os.environ['AGENT_TOKEN']

def verify_token(creds: HTTPAuthorizationCredentials = Depends(security)):
    if creds.credentials != VALID_TOKEN:
        raise HTTPException(status_code=403, detail="Forbidden")

@app.post("/run")
async def run_script(payload: dict, Depends(verify_token)):
    script = payload.get('script')
    allowed = ['disableaccount.ps1', 'collectlogs.ps1', 'resetpassword.ps1']
    if script not in allowed:
        raise HTTPException(status_code=400, detail="Script not allowed")
    result = subprocess.run(
        ['powershell.exe', '-File', f'C:\scripts\{script}', '--target', payload.get('target')],
        capture_output=True, text=True, timeout=60
    )
    return {'stdout': result.stdout, 'stderr': result.stderr, 'returncode': result.returncode}
```

## ✅ Validación Funcional

### Probar ejecución de script

```bash
curl -X POST https://agent-dc01.tudominio.com/run \
  -H "Authorization: Bearer <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "script": "disableaccount.ps1",
    "target": "user.comprometido"
  }'
```

### Verificar tunnel

```bash
cloudflared tunnel list
```

## ⚠️ Consideraciones de Seguridad

- 🔐 **Bearer Token:** validación en cada ejecución
- 📜 **Allowlist estricta:** nunca ejecución libre de scripts
- 🔒 **Túneles salientes:** no hay puertos abiertos hacia internet en endpoints
- ⏱️ **TTL:** acceso remoto con caducidad automática
- 📝 **Auditoría:** cada ejecución registrada en IRIS

## 🚀 Próximos Pasos

1. 🦎 Implementar Velociraptor para colección forense (Fase 5)
2. 📊 Integrar DFIR-IRIS para gestión de caso (Fase 6)
3. 📈 Desplegar OpenSearch Dashboards (Fase 7)
