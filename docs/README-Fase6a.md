# 🛡️ Fase 6a — Despliegue de DFIR-IRIS

> **Objetivo:** desplegar DFIR-IRIS en Docker como plataforma de *case management* DFIR, preparada para recibir casos automáticos desde el orquestador y enlazar evidencias, decisiones y timeline del incidente.

---

## 📑 Índice

- [🎯 Objetivo](#-objetivo)
- [🏗️ Arquitectura](#-arquitectura)
- [🐳 Despliegue en Docker](#-despliegue-en-docker)
- [⚙️ Configuración](#-configuración)
- [🌐 Acceso web](#-acceso-web)
- [🔑 API Key](#-api-key)
- [✅ Validación realizada](#-validación-realizada)
- [➡️ Siguiente paso](#-siguiente-paso)

---

## 🎯 Objetivo

La Fase 6a tiene como finalidad dejar operativa la plataforma DFIR-IRIS en un entorno Docker, lista para la gestión completa de casos de incidente, con acceso web local y preparación para automatización vía API.

IRIS permite crear casos, modificar metadatos, cerrar casos y consultar historial de cambios desde su interfaz y API, por lo que encaja como capa de *case management* del proyecto TFM.

---

## 🏗️ Arquitectura

La arquitectura de esta subfase queda compuesta por:

- **IRIS Web App**, para gestión de casos y evidencias.
- **PostgreSQL**, como base de datos.
- **RabbitMQ**, como cola interna.
- **Nginx**, como frontal HTTPS.
- **oob-network**, para integración con el resto del stack del TFM.

IRIS se despliega con Docker y Docker Compose, usando la configuración base del repositorio oficial y el fichero `.env.model` como referencia.

---

## 🐳 Despliegue en Docker

El despliegue se realiza con el repositorio oficial `dfir-iris/iris-web`, fijando la versión `v2.4.27` y levantando los servicios necesarios con Docker Compose.

### Servicios validados

| Servicio | Estado | Función |
|---|---:|---|
| `db` | ✅ | Base de datos PostgreSQL de IRIS |
| `rabbitmq` | ✅ | Cola de mensajería interna |
| `app` | ✅ | Aplicación principal de IRIS |
| `worker` | ✅ | Procesado asíncrono de tareas |
| `nginx` | ✅ | Frontal web HTTPS |

---

## ⚙️ Configuración

La configuración base se apoya en variables de entorno definidas en `.env`, siguiendo el modelo oficial de IRIS.

### Valores relevantes

| Variable | Valor utilizado |
|---|---|
| `SERVER_NAME` | `iris.local` |
| `INTERFACE_HTTPS_PORT` | `4833` |
| `IRIS_AUTHENTICATION_TYPE` | `local` |
| `IRIS_ADM_USERNAME` | `administrator` |
| `IRIS_ADM_EMAIL` | `admin@iris.local` |

La API de IRIS usa un token tipo Bearer en la cabecera `Authorization`, y cada usuario tiene su propia API key.

---

## 🌐 Acceso web

El acceso web quedó operativo por navegador en:

- `https://iris.local:4833`

Para ello se añadió `iris.local` al fichero `/etc/hosts`, apuntando al host local. La documentación oficial indica que IRIS se accede por HTTPS y que el puerto puede variar según el despliegue.

---

## 🔑 API Key

La cuenta administrativa dispone de API key para automatizar operaciones desde el orquestador. La API de IRIS acepta esa key como token Bearer en el encabezado `Authorization`.

### Uso previsto en Fase 6b

- Crear casos automáticamente.
- Añadir notas y evidencias.
- Registrar eventos en el timeline.
- Cerrar el caso cuando finalice la respuesta.

La documentación oficial de casos de IRIS confirma que se pueden crear casos, modificar metadatos y consultar la historia del caso desde la interfaz y la API.

---

## ✅ Validación realizada

La Fase 6a queda validada con los siguientes puntos:

- IRIS despliega correctamente en Docker.
- La interfaz web responde desde `iris.local`.
- El frontal HTTPS está expuesto en `4833`.
- La autenticación local está operativa.
- La API key del administrador está disponible para automatización.

IRIS soporta la creación de casos con título, descripción corta y cliente asociado, que es precisamente el paso que se automatizará en la Fase 6b.

---

## ➡️ Siguiente paso

El siguiente paso será la **Fase 6b**, donde el orquestador creará automáticamente un caso en IRIS con los datos del incidente `INC-2026-042`, enlazando la evidencia ya almacenada en MinIO desde la Fase 5.

---