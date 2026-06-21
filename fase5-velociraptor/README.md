# 🦖 Fase 5 — Forense Automático con Velociraptor + MinIO

**Proyecto:** TFM — Plataforma OOB de alerta temprana y respuesta a incidentes  
**Fase:** 5 — Captura Forense Automática  
**Fecha:** 2026-06-21  
**Estado:** ✅ Validada en laboratorio, lista para integración con el Orquestador

[![TFM](https://img.shields.io/badge/TFM-Alerta%20Temprana%20OOB-blue)]()
[![Fase](https://img.shields.io/badge/Fase-5-purple)]()
[![Estado](https://img.shields.io/badge/Estado-Validado-success)]()
[![Velociraptor](https://img.shields.io/badge/Velociraptor-0.76.6-brightgreen)]()
[![MinIO](https://img.shields.io/badge/MinIO-Evidence%20Store-yellow)]()
[![Docker](https://img.shields.io/badge/Docker-Compose-black)]()

---

## 📋 Tabla de contenidos

- [🎯 Objetivo de la fase](#-objetivo-de-la-fase)
- [🏗️ Arquitectura](#️-arquitectura)
- [🧱 Componentes desplegados](#-componentes-desplegados)
- [✅ Validaciones realizadas](#-validaciones-realizadas)
- [🪣 MinIO y evidencia](#-minio-y-evidencia)
- [🛰️ Clientes de prueba](#️-clientes-de-prueba)
- [🔁 Flujo operativo](#-flujo-operativo)
- [🧪 Colecciones de prueba](#-colecciones-de-prueba)
- [🧩 Integración con la Fase 2](#-integración-con-la-fase-2)
- [🐛 Incidencias resueltas](#-incidencias-resueltas)
- [📊 Estado final](#-estado-final)
- [📌 Próximos pasos](#-próximos-pasos)

---

## 🎯 Objetivo de la fase

La **Fase 5** implementa la capacidad de **captura forense remota** del proyecto mediante **Velociraptor**, y la persistencia de la evidencia en **MinIO** como repositorio compatible con S3. El objetivo es que, ante un incidente, el sistema pueda recolectar artefactos de manera rápida, reproducible y trazable, sin depender de acceso manual al endpoint.

Esta fase se integra con la arquitectura general del TFM: **n8n / Orquestador** decide cuándo lanzar la colección, **Velociraptor** ejecuta la recolección, **MinIO** conserva el ZIP y sus metadatos, y **IRIS** recibirá después la referencia a la evidencia y el resumen del caso.

---

## 🏗️ Arquitectura

```mermaid
flowchart LR
  ORC[🧠 Orquestador\n(n8n / FastAPI)] -->|Dispara colección| VR[🦖 Velociraptor Server]
  VR -->|Recolecta artefactos| END[🖥️ Clientes\nUbuntu / W11 / W2025]
  VR -->|Exporta ZIP| MINIO[🪣 MinIO\nEvidence Store]
  MINIO -->|manifest + hash| IRIS[🗂️ DFIR-IRIS]
```

La fase se ha validado con una topología de laboratorio basada en **Ubuntu Server** como servidor central y tres clientes de prueba: **Ubuntu Server**, **Windows 11** y **Windows Server 2025**. Todos los equipos están unidos por la red del entorno de pruebas y resuelven `velociraptor.local` correctamente tras la edición del fichero `hosts`.

---

## 🧱 Componentes desplegados

| Componente | Función | Estado |
|---|---|---|
| 🦖 **Velociraptor Server 0.76.6** | Gestión de colecciones forenses | ✅ Operativo |
| 🪣 **MinIO** | Almacenamiento de evidencia | ✅ Operativo |
| 🖥️ **Ubuntu Server** | Cliente de prueba y servicio systemd | ✅ Conectado |
| 🪟 **Windows 11** | Cliente de prueba con MSI | ✅ Conectado |
| 🪟 **Windows Server 2025** | Cliente de prueba con MSI | ✅ Conectado |
| 🧠 **Orquestador** | Lógica de disparo de colecciones | 🔜 Integración pendiente |

---

## ✅ Validaciones realizadas

Durante el desarrollo de la fase se han validado los siguientes puntos:

- Despliegue de **Velociraptor Server 0.76.6** en Docker.
- Acceso correcto a la GUI en `https://velociraptor.local:8889`.
- Generación de `client.config.yaml` desde la configuración del servidor.
- Instalación del cliente en Ubuntu como servicio systemd.
- Generación e instalación del **MSI de Windows** en W11 y W2025.
- Resolución de nombre mediante el fichero `hosts` en los equipos Windows.
- Conexión estable de los tres clientes en la GUI de Velociraptor.
- Ejecución de colecciones manuales de prueba.
- Creación del bucket `evidence` en MinIO.

---

## 🪣 MinIO y evidencia

La evidencia forense se almacena en MinIO en una estructura jerárquica pensada para facilitar la trazabilidad y el análisis posterior.

```text
/evidence/
  {incident_id}/
    {host}/
      {timestamp}/
        velociraptor_collection.zip
        manifest.json
        sha256.txt
```

### Archivos esperados

- `velociraptor_collection.zip`: ZIP exportado con los resultados de la colección.
- `manifest.json`: metadatos del caso, host, perfil de colección y sello temporal.
- `sha256.txt`: hash de integridad del ZIP o de la evidencia exportada.

Este esquema permite enlazar la salida de Velociraptor con el caso DFIR en fases posteriores.

---

## 🛰️ Clientes de prueba

### Ubuntu Server

El cliente se instaló como servicio con `systemd` y se verifica su persistencia mediante `systemctl status velociraptor_client`. El cliente quedó operativo y reportando a la GUI.

### Windows 11

Se generó un MSI personalizado desde la GUI de Velociraptor y se instaló correctamente en el host de pruebas. El equipo aparece como cliente activo.

### Windows Server 2025

Se usó el mismo MSI generado para W11, ajustando previamente la resolución del nombre mediante `hosts`. Tras ello, el servidor quedó visible y operativo en la GUI.

---

## 🔁 Flujo operativo

El flujo validado en esta fase es el siguiente:

1. El analista identifica el host objetivo desde la GUI o desde el Orquestador.
2. Se lanza una colección de Velociraptor con el perfil adecuado.
3. El cliente ejecuta el artefacto y devuelve los resultados al servidor.
4. Velociraptor genera el ZIP exportable.
5. El ZIP y el manifiesto se guardan en MinIO.
6. El Orquestador podrá registrar la referencia a la evidencia en IRIS.

Este flujo puede ejecutarse manualmente desde la GUI o automatizarse más adelante desde el Orquestador de la Fase 2.

---

## 🧪 Colecciones de prueba

Se realizaron colecciones básicas para verificar la conectividad y el funcionamiento del pipeline:

- `Windows.System.Pslist` en Windows 11.
- `Windows.System.Pslist` en Windows Server 2025.
- `Linux.Sys.Pslist` en Ubuntu Server.

Estas colecciones sirven como validación mínima de que el servidor, los clientes y la GUI están funcionando correctamente.

---

## 🧩 Integración con la Fase 2

La **Fase 2** del proyecto define el **Orquestador** como la capa de automatización y coordinación del sistema, implementada con **n8n** y complementada por servicios auxiliares en **FastAPI** cuando sea necesario. Por tanto, la Fase 5 no debe crear un orquestador paralelo; debe integrarse con la lógica ya definida en la Fase 2.

### Enfoque recomendado

- **n8n**: motor de automatización principal.
- **FastAPI**: microservicio auxiliar para exponer operaciones técnicas, si conviene.
- **Velociraptor**: ejecución de la colección forense.
- **MinIO**: persistencia de la evidencia.
- **IRIS**: trazabilidad y gestión del caso.

### Qué se hará desde la Fase 2

El Orquestador podrá:
- seleccionar el perfil de colección según el incidente,
- invocar la colección de Velociraptor,
- supervisar el estado de la tarea,
- recibir el ZIP generado,
- cargarlo en MinIO,
- y dejar la referencia en IRIS.

### Sobre el script Python adjunto

El fichero `orchestrator_velociraptor_example.py` se mantiene solo como **ejemplo de integración** o base de microservicio, pero no debe entenderse como un segundo orquestador completo. La arquitectura final del proyecto se apoya en **n8n + Orquestador** como punto de coordinación central.

---

## 🐛 Incidencias resueltas

| Incidencia | Causa | Solución |
|---|---|---|
| Imagen Docker inexistente | Se intentó usar una imagen no oficial | Se construyó una imagen propia con el binario oficial 0.76.6 |
| `--plain-http` inválido | Flag obsoleto/no soportado | Se eliminó del arranque y se ajustó la configuración |
| Fichero `server.config.yaml` no encontrado | Volumen vacío tras recreación | Se regeneró la configuración con el binario actual |
| Puerto `8001` ocupado | Contenedor/proxy previo seguía activo | Se liberó el puerto y se reinició el servicio |
| `Permission denied` al crear `client.config.yaml` | Redirección sin permisos | Se usó `sudo tee` o se corrigieron permisos |
| `velociraptor: Is a directory` | Conflicto de nombre con un directorio local | Se renombró el binario y se instaló en `/usr/local/bin` |
| `service install` no funcionaba | Subcomando no válido para el flujo usado | Se creó un servicio systemd manual |
| Windows Server 2025 en warning | `hosts` revertido a versión anterior | Se restauró la entrada correcta y se vació la caché DNS |

---

## 📊 Estado final

| Elemento | Estado |
|---|---|
| Velociraptor Server | ✅ Operativo |
| MinIO | ✅ Operativo |
| Cliente Ubuntu | ✅ Conectado |
| Cliente Windows 11 | ✅ Conectado |
| Cliente Windows Server 2025 | ✅ Conectado |
| Colecciones de prueba | ✅ Ejecutadas |
| Bucket `evidence` | ✅ Creado |
| Integración con Orquestador | 🔜 Pendiente de automatización |

---

## 📌 Próximos pasos

1. Integrar el Orquestador de Fase 2 con Velociraptor mediante un endpoint HTTP o servicio auxiliar.
2. Automatizar la exportación del ZIP y la subida a MinIO.
3. Generar `manifest.json` y `sha256.txt` de forma automática.
4. Dejar listo el enlace de la evidencia para la futura fase de DFIR-IRIS.

---

## 📚 Referencias

- [Velociraptor Docs](https://docs.velociraptor.app/)
- [Velociraptor Releases](https://github.com/Velocidex/velociraptor/releases)
- [MinIO Docs](https://min.io/docs/)
- [DFIR-IRIS](https://dfir-iris.org/)
- [n8n Docs](https://docs.n8n.io/)

---

**Última actualización:** 2026-06-21  
**Estado:** ✅ Fase 5 validada en laboratorio | 🔜 Integración con Fase 2 pendiente
