# Medición · Postura de red del host del enclave

**Fecha de la medición:** 2026-09-23. Los puertos de RustDesk (21115-21119) y
las interfaces del host son del 2026-09-24.
**Método:** `sudo ss -tlnp`, `sudo ss -ulnp` y `docker ps` en el host del
enclave. Las interfaces salen del log de `tailscaled` del 2026-09-24. El
operador aportó las salidas; este documento las transcribe y no añade ninguna
medición propia.
**Origen:** hallazgos A-8, A-11 y A-15 y verificaciones D-4 y D-6 de
`docs/AUDITORIA-CIERRE-2026-09-23.md`.

---

## 1. Interfaces del host

| Interfaz | Dirección (medida) | Uso (según la documentación) |
|---|---|---|
| `ens33` | `192.168.0.70/24` | LAN del KVM (`glkvm_cloud`, GL-RM1 en `192.168.0.36`) |
| `ens34` | `192.168.127.138/24` | Red del laboratorio: DC01 y W11; es la IP con la que el W11 resuelve los nombres del enclave. Traefik escucha en todas las interfaces (`0.0.0.0`) |
| `tailscale0` | `100.64.0.1/32` | Tailnet de Headscale |

`192.168.0.70` y `192.168.127.138` son **el mismo host** en dos interfaces
distintas. Así se resuelve la discrepancia A-15 de la auditoría de cierre: las
dos IP aparecen en la documentación porque las dos existen.

---

## 2. Puertos a la escucha

| Protocolo | Dirección | Puerto | Proceso / contenedor | Nota |
|---|---|---|---|---|
| TCP | `0.0.0.0` y `[::]` | 22 | `sshd` del host | |
| TCP | `0.0.0.0` y `[::]` | 80, 443 | `traefik` | Borde del enclave |
| TCP | `0.0.0.0` y `[::]` | 1514, 1515 | `single-node-wazuh.manager-1` | Agentes y registro |
| TCP | `0.0.0.0` y `[::]` | 55000 | `single-node-wazuh.manager-1` | API de Wazuh |
| TCP | `0.0.0.0` y `[::]` | 9200 | `single-node-wazuh.indexer-1` | Indexador |
| TCP | `0.0.0.0` y `[::]` | 9000 | `minio` | API S3, sin TLS |
| TCP | `0.0.0.0` y `[::]` | 8001 | `velociraptor` | Frontend de agentes |
| TCP | `100.64.0.1` | 4833 | `iriswebapp_nginx` | Solo tailnet |
| TCP | `100.64.0.1` | 21115-21119 | `rustdesk-hbbs`, `rustdesk-hbbr` | Solo tailnet |
| TCP | `192.168.0.70` | 5912, 10443 | `glkvm_cloud` | Plano del KVM, LAN |
| TCP | `127.0.0.1` | 8080 | `traefik` | Dashboard |
| TCP | `127.0.0.1` | 9443 | `portainer` | |
| TCP | `127.0.0.1` | 8020 | `orchestrator` | |
| TCP | `127.0.0.1` | 8090 | `headscale` | Servidor de control (8080 interno) |
| TCP | `127.0.0.1` | 1280, 12443 | `misp-docker-misp-core-1` | Solo loopback, no cerrados |
| UDP | `0.0.0.0` y `[::]` | 514 | `single-node-wazuh.manager-1` | Syslog sin autenticación |
| UDP | `0.0.0.0` y `[::]` | 3478 | `headscale` | STUN/DERP |
| UDP | `0.0.0.0` y `[::]` | 41641 | `tailscaled` | |
| UDP | `100.64.0.1` | 21116 | `rustdesk-hbbs` | |
| UDP | `0.0.0.0` | 21119, 40034 | `rustdesk --server` del host | **Cliente** de escritorio RustDesk, no el servidor |

El `127.0.0.1:8090` es el contenedor `headscale` (su 8080 interno), no
`headscale-ui`.

Los puertos de RustDesk son los que había después de la reparación del
2026-09-24 (`docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md`). En la
medición del 2026-09-23 esos contenedores estaban sin red y no publicaban
ningún puerto.

---

## 3. Puertos que no escuchan

| Puerto | Qué publicaba antes | Estado medido el 2026-09-23 |
|---|---|---|
| TCP 4443 | Dashboard de Wazuh, publicado directamente | Cerrado. Según la configuración, hoy se sirve por Traefik (`wazuh.oob.local`) |
| TCP 9001 | Consola de MinIO | Cerrado. Según la configuración, hoy se sirve por Traefik |
| TCP 8889 | GUI de Velociraptor | Cerrado |

---

## 4. Ruido del host ajeno al enclave

Procesos del escritorio del host que aparecen en `ss` y no forman parte del
enclave: `cupsd` (631), `systemd-resolved` (53), `avahi-daemon` (5353), el
navegador y `code`. El `rustdesk --server` de la tabla de la sección 2 también
es ajeno: es el cliente de escritorio en modo servicio
(`docs/HALLAZGO-rustdesk-contenedores-sin-red-2026-09-23.md:104-108`).

---

## 5. Autenticación en el borde (Authelia)

Medido sin sesión el 2026-09-24:

| Nombre | Respuesta |
|---|---|
| `chat.oob.local` | `302` hacia `auth.oob.local` |
| `n8n.oob.local` (editor y `/rest/*`) | `302` hacia `auth.oob.local`, desde el commit `655162f` |
| `noexiste.oob.local` | `404` (control negativo) |

Los demás servicios con regla en `fase1-infraestructura/authelia/configuration.yml`
(minio, wazuh, hs, misp, iris y portainer) **no se han medido** (D-6 de la
auditoría de cierre). Para ellos solo consta la configuración.

---

## 6. Alcance: lo que esta medición añade

Hasta esta medición, la documentación de postura de red del proyecto solo
razonaba sobre **TCP en IPv4**. La medición muestra dos cosas que quedaban
fuera:

- **IPv6.** Todo lo que se expone en `0.0.0.0` también se expone en `[::]`: la
  superficie de IPv4 se duplica en IPv6.
- **UDP.** Tiene superficie propia: 514 (syslog de Wazuh, sin autenticación) y
  3478 (STUN/DERP de Headscale) en todas las interfaces.

Queda **declarado, no remediado**. Ningún control del proyecto comprueba hoy
esas dos superficies.
