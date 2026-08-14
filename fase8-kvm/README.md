# 🎯 Fase 8 · Plan C - KVM y Hardening Final

> [!NOTE]
> **🎯 Objetivo de la fase**  
> Implementar resiliencia máxima con fallback a KVM físico cuando RustDesk falle, y hardening final del enclave con mTLS y pruebas de resiliencia.

> [!TIP]
> Esta fase asegura que el sistema pueda operar incluso si el acceso remoto por software (RustDesk) no es confiable o el endpoint está completamente comprometido.

## 📋 Estado

- [x] 🖥️ GL.iNet KVM integrado en inventario del Orquestador
- [x] 🔄 Flujo fallback automático: RustDesk timeout → oferta KVM
- [x] ✅ Política 2-person rule para powerreset
- [x] 🔐 Hardening Authelia: revisión de secretos y tokens
- [x] 🔒 mTLS en Cloudflare Access para túneles DC
- [ ] 🧪 Pruebas de resiliencia completas
- [ ] 📚 Documentación de canales de backup

## 🏗️ Arquitectura

```text
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│  Orquestador │────▶│  RustDesk    │────▶│   Endpoint   │
│   Fallback   │     │   Timeout    │     │   DC/W2025   │
└──────────────┘     └──────────────┘     └──────────────┘
        │
        │ (si RustDesk falla)
        ▼
┌──────────────┐     ┌──────────────┐
│  GL.iNet KVM │────▶│  Power Reset │
│   Plan C     │     │   Físico     │
└──────────────┘     └──────────────┘
```

## 🔧 Flujo Fallback

### Paso 1: RustDesk habilitado
- Orquestador solicita aprobación: "Habilitar RustDesk en HOST-X durante 30 min"
- 1 aprobación (IR Lead)
- Active Response Wazuh habilita RustDesk con credencial efímera
- Timeout: 120 segundos para conectar

### Paso 2: Timeout RustDesk
- Si no hay conexión en 120s → 2 intentos
- Si falla → ofrecer Plan C (KVM)

### Paso 3: Plan C - KVM
- 1 aprobación (IR Lead) para sesión KVM
- 2 aprobaciones (IR Lead + IT Ops) para powerreset
- Se publica enlace KVM en War Room
- Se registra en IRIS

## ⚙️ Configuración Aplicada

### GL.iNet KVM

```python
# Integración en Orquestador
class GLKVM:
    def __init__(self, host, user, password):
        self.host = host
        self.session = requests.Session()
        self.session.auth = (user, password)
    
    def power_cycle(self):
        self.session.post(f"http://{self.host}/api/power/cycle")
    
    def get_status(self):
        return self.session.get(f"http://{self.host}/api/status").json()
```

### mTLS Cloudflare Access

```yaml
# config.yml cloudflared
tunnel: <TUNNEL_UUID>
credentials-file: C:\agent\.cloudflared\<UUID>.json
access:
  - hostname: agent-dc01.tudominio.com
    policy:
      - require:
          - certificate:
              prefix: dc-client-cert
```

## ✅ Validación Funcional

### Probar fallback RustDesk → KVM

1. Simular fallo de RustDesk (endpoint apagado)
2. Verificar que Orquestador ofrece KVM automáticamente
3. Aprobar sesión KVM
4. Verificar que se publica enlace en War Room

### Probar powerreset

1. Solicitar powerreset con 2 aprobaciones
2. Verificar que se ejecuta en GL.iNet KVM
3. Verificar registro en IRIS

## ⚠️ Consideraciones de Seguridad

- 🔐 **2-person rule:** powerreset requiere 2 aprobaciones
- 🔒 **mTLS:** segunda capa de autenticación en túneles
- 📝 **Auditoría:** cada acción KVM registrada en IRIS
- 🧪 **Pruebas de resiliencia:** validar fallbacks periódicamente

## 🚀 Próximos Pasos

1. 🧪 Ejecutar pruebas de resiliencia completas
2. 📚 Documentar canales de backup (si Rocket.Chat cae)
3. 📊 Refinar dashboard de métricas (Fase 7)
4. 🎓 Preparar defensa del TFM
