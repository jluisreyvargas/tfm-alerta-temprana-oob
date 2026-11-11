# Despliegue del enclave desde cero

Instalador para levantar el enclave completo sobre un **Ubuntu recién
instalado**. Fuente de verdad: [`docs/despliegue/INVENTARIO-despliegue.md`](../docs/despliegue/INVENTARIO-despliegue.md).

> [!CAUTION]
> **No lo ejecutes en el laboratorio.** Genera secretos nuevos, una CA nueva y
> reescribe ficheros versionados. El script aborta, sin opción de forzar, si
> encuentra un `.env`, la clave de la CA o algún contenedor de Docker. Úsalo
> solo en un clon recién hecho, dedicado al despliegue.

## Estado

| Etapa | Contenido | Estado |
|---|---|---|
| 0 | Host: paquetes, parámetros, red Docker, `/etc/hosts`, imágenes | implementada |
| 1 | Material previo: secretos, `.env`, PKI, ficheros, usuarios de Authelia | implementada |
| 2 – 10 | Arranque de servicios, integraciones y paquete de salida | **no implementadas** |

Las etapas siguen la numeración de la sección 4.5 del inventario. Ninguna de
las dos implementadas arranca un servicio del enclave.

## Uso

```bash
git clone <repositorio> && cd tfm-alerta-temprana-oob
```

```bash
./deploy/deploy.sh
```

| Orden | Qué hace |
|---|---|
| `deploy.sh` | Continúa desde la primera etapa no completada |
| `deploy.sh --list` | Lista las etapas y su estado |
| `deploy.sh --only N` | Ejecuta solo la etapa N, aunque ya esté hecha |
| `deploy.sh --from N` | Ejecuta desde la etapa N en adelante |
| `deploy.sh selftest` | Pruebas de las funciones puras; sin `sudo` y sin Docker |

Se ejecuta con tu usuario, no como root: el script pide `sudo` cuando lo
necesita. Es interactivo y necesita un terminal.

## Qué pregunta

- **Primera ejecución:** confirmación de que el clon es solo de despliegue. Con
  ella instala un hook `pre-commit` que rechaza cualquier commit en ese clon.
- **Etapa 0:** IP de LAN del KVM, IP del enclave (donde escucha Traefik), IP
  esperada del tailnet, IP del GL-RM1, usuario y ruta del repositorio. El
  dominio es fijo: `oob.local`.
- **Etapa 1:** claves de API de VirusTotal y AbuseIPDB (se pueden omitir) y los
  usuarios de Authelia. Las contraseñas se piden sin eco o se generan.

Cada bloque de preguntas muestra un valor por defecto y pide confirmar el
conjunto antes de escribir nada.

## Dónde deja las cosas

| Ruta | Contenido |
|---|---|
| `deploy/.state/params.env` | Parámetros confirmados |
| `deploy/.state/secrets.env` | Almacén único de secretos, modo `600` |
| `deploy/.state/etapa-N.hecha` | Marca de etapa completada |
| `deploy/.state/deploy.log` | Registro. No contiene secretos |
| `deploy/out/` | Paquete para DC01, W11 y el GL-RM1 (etapa 10) |

`deploy/.state/` y `deploy/out/` están en `.gitignore`. Las contraseñas de
Authelia que el script genere quedan en el almacén como
`AUTHELIA_PASSWORD_<usuario>`.

## Comportamiento

- **Reanudable.** Una etapa completada deja su marca y no se repite salvo con
  `--only` o `--from`.
- **Idempotente.** Repetir una etapa no regenera ningún secreto ni ninguna
  clave: lo que existe y es válido se conserva.
- **Comprobado.** Cada etapa termina con sus comprobaciones y no deja la marca
  si alguna falla. El fallo dice qué se esperaba y qué se encontró.
- **Sin secretos a la vista.** Ningún valor se imprime ni se registra.

## Ficheros versionados que modifica

La etapa 1 sustituye por los de la CA nueva `oob-rootCA.crt` (fase 1 y n8n),
`irisRootCACert.pem` y `ca-bundle-oob.crt`. Son públicos; el hook impide
subirlos. Los cambios al proyecto se hacen en el clon de trabajo, no en el de
despliegue.

## Si algo falla

Lee el mensaje, corrige y vuelve a ejecutar `./deploy/deploy.sh`: retoma en la
etapa que falló. Para volver a preguntar los parámetros, quita la línea
`PARAMS_CONFIRMADOS` de `deploy/.state/params.env` y ejecuta `--only 0`.
