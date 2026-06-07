# Fase 4 — Conectividad privada, DC Agent y Break-Glass RustDesk

## Objetivo

La Fase 4 construye el bloque de conectividad privada y operación remota controlada del proyecto TFM. En esta fase se utiliza **Tailscale + Headscale** como base de conectividad segura entre el orquestador y los Domain Controllers Windows Server 2025, y se integran los mecanismos de ejecución controlada y acceso remoto temporal necesarios para la respuesta a incidentes.

El propósito es disponer de una capa out-of-band capaz de:
- conectar el orquestador con los DCs sin depender de la red corporativa,
- ejecutar acciones autorizadas sobre los DCs de forma autenticada,
- habilitar acceso remoto break-glass con TTL,
- y registrar toda la actividad para auditoría y trazabilidad.

## Contexto dentro del proyecto

La Fase 4 se sitúa sobre la infraestructura base ya preparada en fases previas y sirve como puente entre la coordinación de incidentes y la intervención técnica sobre los DCs.

Esta fase permite que el sistema pase de la simple detección y coordinación a la **actuación remota controlada**, manteniendo el enfoque out-of-band del TFM.

## Componentes principales

- **Tailscale**: conectividad privada entre nodos del entorno.
- **Headscale**: plano de control autogestionado para la tailnet.
- **DC Agent Python**: ejecución controlada de scripts permitidos.
- **cloudflared**: túnel saliente seguro hacia el agente del DC.
- **NSSM**: arranque del agente Python como servicio de Windows.
- **RustDesk Server OSS**: acceso remoto temporal break-glass.
- **Wazuh Active Response**: activación y revocación con TTL.
- **Rocket.Chat**: canal de aprobación y notificación.
- **Orquestador**: coordinación, estado y trazabilidad.
- **IRIS**: registro de acciones, sesiones y evidencias.

## Subfases de la Fase 4

### Fase 4a — Headscale
Despliegue del controlador Headscale para gestionar la red privada de Tailscale bajo control propio.

Documento detallado:
[README Fase 4a](docs/README-fase4a-headscale.md)

### Fase 4b — Tailnet de orquestador y DC
Enrolamiento y validación de conectividad de los nodos `orchestrator-tfm` y `dc01-tfm` dentro de la tailnet.

Documento detallado:
[README Fase 4b](docs/README-fase4b-tailnet.md)

### Fase 4c — DC Agent
Despliegue del agente Python en el DC para ejecutar scripts bajo allowlist y autenticación por token.

Documento detallado:
[README Fase 4c](docs/README-fase4c-dc-agent.md)

### Fase 4d — Integración n8n
Orquestación del flujo n8n → DC Agent → Rocket.Chat para automatizar aprobaciones y ejecuciones.

Documento detallado:
[README Fase 4d](docs/README-fase4d-n8n.md)

### Fase 4e — RustDesk break-glass
Despliegue de RustDesk self-hosted para acceso remoto temporal con TTL, revocación automática y trazabilidad.

Documento detallado:
[README Fase 4e](docs/README-fase4e-rustdesk-breakglass.md)

## Arquitectura resumida

El flujo funcional de esta fase es el siguiente:

1. El orquestador y el DC se unen por **Tailscale** sobre **Headscale**.
2. El operador solicita una acción o acceso en Rocket.Chat.
3. El Orquestador valida la solicitud y registra el estado.
4. Si la acción requiere ejecución técnica, el Orquestador llama al DC Agent por el canal privado o por el túnel seguro definido.
5. El DC Agent ejecuta únicamente scripts permitidos.
6. Si la acción requiere acceso remoto, se activa RustDesk bajo TTL.
7. El resultado vuelve al Orquestador y se publica en el canal.
8. Todo queda registrado en IRIS para auditoría y trazabilidad.

## Relación entre subfases

Las subfases se apoyan entre sí y no deben interpretarse como piezas aisladas:

- **Headscale** establece la base de red privada.
- **Tailscale** permite el canal de conectividad entre nodos.
- **DC Agent** aporta ejecución controlada en el DC.
- **n8n** automatiza la secuencia operacional.
- **RustDesk** habilita acceso remoto temporal break-glass.

En conjunto, la Fase 4 representa el bloque de operación remota segura sobre el DC dentro del proyecto TFM.

## Seguridad y control

La fase aplica varios controles clave:

- Conectividad privada con **Tailscale + Headscale**.
- Acceso remoto temporal con TTL.
- Ejecución restringida a scripts de allowlist.
- Autenticación mediante Bearer Token.
- Servicios persistentes mediante NSSM.
- Registro de actividad en IRIS.
- Revocación automática de accesos al finalizar la ventana autorizada.

## Estado actual

La Fase 4 queda orientada a un flujo estable de operación remota controlada sobre el DC, con documentación separada por subfases para mantener claridad, trazabilidad y reutilización.

## Navegación de documentación

- [README Fase 4a](docs/README-fase4a-headscale.md)
- [README Fase 4b](docs/README-fase4b-tailnet.md)
- [README Fase 4c](docs/README-fase4c-dc-agent.md)
- [README Fase 4d](docs/README-fase4d-n8n.md)
- [README Fase 4e](docs/README-fase4e-rustdesk-breakglass.md)