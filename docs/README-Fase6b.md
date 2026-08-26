# 🧩 Fase 6b — Validación del caso y trazabilidad en DFIR-IRIS

> **Objetivo:** validar la gestión operativa del caso en DFIR-IRIS usando el incidente `INC-2026-042`, enlazando la evidencia producida en la Fase 5 con el caso manual creado en IRIS y registrando los primeros elementos de trazabilidad del incidente.

---

## 📑 Índice

- [🎯 Objetivo](#-objetivo)
- [🧱 Contexto de partida](#-contexto-de-partida)
- [🗂️ Caso validado en IRIS](#️-caso-validado-en-iris)
- [📝 Evidencia y timeline](#-evidencia-y-timeline)
- [✅ Validación realizada](#-validación-realizada)
- [➡️ Siguiente paso](#️-siguiente-paso)

---

## 🎯 Objetivo

La Fase 6b tiene como finalidad comprobar que DFIR-IRIS puede actuar como capa de **case management** del TFM, manteniendo un caso activo, una nota de evidencia y un evento de timeline asociados al incidente trabajado en fases anteriores.

La documentación oficial de IRIS describe la gestión de casos y notas como parte central de la operativa del sistema, lo que encaja con la arquitectura planteada para enlazar alerta, análisis y evidencia forense.

---

## 🧱 Contexto de partida

Antes de esta subfase ya existía una evidencia válida generada en Fase 5, almacenada en MinIO en la ruta `evidence/INC-2026-042/HOST-DC01/20260625T185518Z/`, junto con `manifest.json` y `sha256.txt`.

Además, la Fase 6a había dejado IRIS desplegado por Docker, accesible por web, con autenticación local activa y API key administrativa disponible para pruebas de integración.

---

## 🗂️ Caso validado en IRIS

Se creó manualmente un caso operativo en IRIS para evitar el bloqueo por las diferencias entre endpoints documentados y endpoints realmente expuestos por la versión desplegada. La propia conversación de validación mostró que el listado de casos vía `/manage/cases/list` sí estaba operativo, mientras que algunos endpoints de creación y notas devolvían errores o rutas no encontradas según la versión.

### Datos del caso

| Campo | Valor |
|---|---|
| Case name | `#2 - INC-2026-042` |
| Case description | `Test Case TFM` |
| Customer | `IrisInitialClient` |
| SOC ID | `1` |
| Case ID | `2` |
| Case UUID | `f4a408e0-a8f7-4cec-bcaa-afe8220b0b2e` |

Este caso constituye el punto de unión entre la evidencia automatizada de Fase 5 y la gestión formal del incidente dentro de IRIS.

---

## 📝 Evidencia y timeline

Dentro del caso se validaron dos acciones manuales en la interfaz de IRIS:

- creación de una **nota de evidencia** con los datos de la colección forense;
- creación de un **evento de timeline** para registrar el inicio del incidente.

La documentación de IRIS contempla explícitamente el uso de notas y operaciones de caso como mecanismo de documentación y seguimiento del incidente.

### Nota de evidencia registrada

La nota incorporó los siguientes elementos funcionales:

- `Incident ID`: `INC-2026-042`
- `Host`: `HOST-DC01`
- `Profile`: `credential_dump_collection`
- artefactos: `Windows.System.Pslist` y `Windows.Memory.Acquisition`
- ubicación MinIO: `evidence/INC-2026-042/HOST-DC01/20260625T185518Z/`
- hash SHA-256: `2fc7f85ceed2e4a1bc5081a1691d231961b1ba093a7ef8671f4da34f601080f9`
- operador: `orchestrator_v1`
- origen: `n8n-fase5`

Esta nota deja constancia operativa de la evidencia recolectada y vincula el caso IRIS con el repositorio de evidencia mantenido en MinIO.

### Evento de timeline registrado

El timeline del caso recibió un primer evento asociado a la alerta inicial de tipo **SSH Brute Force**, con el objetivo de representar cronológicamente el inicio del tratamiento del incidente en IRIS.

Con este evento, el caso deja de ser solo un contenedor administrativo y pasa a reflejar la secuencia básica alerta → análisis → evidencia → gestión del caso.

---

## ✅ Validación realizada

La Fase 6b puede darse por validada en su parte funcional básica con los siguientes puntos:

- el caso `#2 - INC-2026-042` existe en IRIS;
- la autenticación administrativa y la consulta API quedaron verificadas con éxito mediante `/manage/cases/list`.
- la evidencia de Fase 5 quedó enlazada manualmente al caso mediante una nota operativa.
- el incidente dispone ya de un primer evento de timeline dentro de IRIS.
- IRIS queda integrado como capa de trazabilidad y gestión sobre el flujo previo Velociraptor → n8n → MinIO.

---

## ➡️ Siguiente paso

El siguiente paso lógico consiste en conectar **n8n** con IRIS para que el orquestador pueda registrar automáticamente la referencia del caso, la evidencia y el estado del incidente, incluso si algunas operaciones avanzadas deben mantenerse inicialmente en modo manual por compatibilidad de endpoints entre versiones.

A nivel de arquitectura del TFM, esta continuación permite cerrar el flujo completo: **alerta → orquestación → evidencia en MinIO → caso en IRIS → trazabilidad del incidente**.
