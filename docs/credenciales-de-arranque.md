# Credenciales de arranque · dos hallazgos y un patrón

**Origen:** ninguno de los dos se buscó. Ambos aparecieron tirando de hilos sobre
otra cosa, durante el trabajo de las mejoras 2 y 6 de la Fase 8.

**Por qué un documento propio:** no pertenecen a ninguna mejora. El primero
afecta al tailnet completo; el segundo, al ancla de confianza de todos los
servicios del enclave. Enterrarlos en un documento titulado "endurecimiento del
dispositivo" o "validación TLS del canal rtty" los haría invisibles para quien
buscara por el lado correcto.

---

## 1. Clave de preautorización reutilizable en Headscale

**Cómo apareció.** Comprobando si el estado de Tailscale persistido en el GL-RM1
(`tailscaled.state`, 2122 B) permitía reincorporar el dispositivo al tailnet sin
reprovisionar. La respuesta al dispositivo era que no —el nodo no figura en
Headscale— pero la comprobación del lado del servidor reveló otra cosa.

**El hallazgo.** `headscale preauthkeys list` mostraba diez claves. La ID 1 era:

| Propiedad | Valor |
|---|---|
| Reutilizable | **sí** |
| Usada | no |
| Creada | 31 de mayo de 2026 |
| Caducidad | 31 de mayo de 2027 |

Un año de validez y reutilización ilimitada. Cualquiera con acceso a esa clave
podía incorporar nodos al tailnet donde viven `orchestrator-tfm`, `dc01-tfm` y
`analyst-w11`, sin intervención del operador.

**Lo que contradecía.** La decisión **D1** del informe de auditoría de Fase 8 —el
KVM queda fuera del tailnet— es una de las dos sobre las que se sostiene RA-1, el
riesgo aceptado del hook de autorización. D1 estaba implementada sólo en el
cliente, mediante `{"enable": false}` en `tailscale.json`. En el servidor había
una vía de alta abierta.

**Acción.** `headscale preauthkeys expire -i 1`. Verificado después: la clave
figura expirada y los tres nodos siguen `online`, lo que confirma que una
preauthkey autoriza el registro inicial y no sostiene la sesión. Las ID 2-7
estaban caducadas desde agosto; las 8, 9 y 10 están usadas y no son reutilizables.

**Estado resultante.** D1 se sostiene ahora en los dos lados. Y las altas futuras
exigen crear una clave de un solo uso en el momento (`headscale preauthkeys
create`); si algún procedimiento de la memoria describe el alta con clave
reutilizable, hay que actualizarlo.

---

## 2. La clave privada de la CA raíz, montada en un contenedor de terceros

**Cómo apareció.** Preparando la mejora 2. Antes de sustituir `-sx` por `-s -C`
en el cliente, había que saber qué certificado presenta rttys en el puerto 5912.

```
subject = C=ES, O=TFM Enclave OOB, OU=Seguridad, CN=OOB Enclave Root CA
issuer  = C=ES, O=TFM Enclave OOB, OU=Seguridad, CN=OOB Enclave Root CA
No extensions in certificate
```

Subject e issuer idénticos: rttys presentaba **la CA raíz del enclave como
certificado de servidor**.

**Confirmación de que era la misma.** Huella SHA-256 idéntica a
`fase1-infraestructura/traefik/certs/oob-rootCA.crt`, y `cmp` byte a byte entre
`oob-rootCA.key` y `docker-compose/certificate/glkvm.key`: misma clave.

**El alcance.** `glkvm.key` estaba montada en `glkvm_cloud`, una imagen del
fabricante del KVM fijada por digest. Quien comprometiera ese contenedor podía
firmar certificados válidos para cualquier servicio del enclave: Wazuh, IRIS,
Velociraptor, MISP, Traefik — todo lo que confía en `ca-bundle-oob.crt`.

El enclave existe para vigilar un dominio potencialmente comprometido, y la pieza
de terceros tenía la llave maestra del ancla de confianza.

**Y explicaba el `-x`.** Un certificado sin SAN, sin `basicConstraints` de
servidor y sin `extendedKeyUsage` no valida contra ningún verificador. El
`--insecure` del cliente no era negligencia: era lo único que hacía funcionar el
canal. La mejora 2 era imposible mientras el servidor presentara eso.

**Acción.** Emitido `glkvm-cloud.crt` con `CN=glkvm-cloud.oob.local`, SAN
`DNS:glkvm-cloud.oob.local, DNS:kvm.oob.local, DNS:glkvm_cloud, DNS:localhost,
IP:192.168.0.70, IP:127.0.0.1`, `extendedKeyUsage = serverAuth`, firmado por la
CA. Sustituido el par en `docker-compose/certificate/` y recreado el contenedor.

**Alcance del cambio, acotado antes de aplicarlo.** `config.go:121` fija la ruta
del certificado en código —no hay clave de `rttys.conf` que redirigir— y tres
listeners la consumen: `api.go:335` (8180), `http.go:108` (10443) y
`device.go:176` (5912). Pero los dos primeros la condicionan a
`!cfg.ReverseProxyEnabled`, y `REVERSE_PROXY_ENABLED=true` en `.env`, de modo que
van en claro tras Traefik. **Sólo el 5912 usa el certificado.** Verificado
también por sondeo: el 10443 no responde TLS.

**Verificado tras el cambio.** El 5912 presenta `glkvm-cloud.oob.local` emitido
por la CA; el dispositivo sigue online; rttys responde. La clave raíz ya no está
en el contenedor.

**Comprobación de exposición.** Ninguna de las dos rutas de la clave está
versionada: `*.key` en `fase1-infraestructura/.gitignore` y `**/certificate/` en
el `.gitignore` raíz. La clave nunca llegó a GitHub.

---

## 3. El patrón

Los dos casos tienen la misma forma:

1. **Creados durante el arranque de una fase.** La preauthkey es del 31 de mayo;
   el montaje del certificado, del 28 de agosto. Ambos anteriores a las
   decisiones de arquitectura que contradicen.
2. **Funcionaban.** Ninguno producía error. El tailnet operaba; el canal rtty
   conectaba. Un sistema que funciona no invita a revisar por qué.
3. **Contradecían un principio que el proyecto afirma cumplir.** D1 —el KVM fuera
   del tailnet— y el principio de que el ancla de confianza es propia y está bajo
   control del enclave.
4. **Ninguna revisión los encontró.** No aparecen en el informe de auditoría de
   Fase 8 ni en el reconocimiento de las APIs, que fueron revisiones deliberadas
   y detalladas. Aparecieron por casualidad, tirando de hilos sobre otra cosa.

**La observación.** Las revisiones de seguridad por fases examinan lo que la fase
construye. Una credencial creada para poner algo en marcha —una clave de alta
para registrar los primeros nodos, un par de certificados para que el contenedor
arranque— no pertenece a ninguna fase en particular: se crea antes de que haya
arquitectura que revisar, y después queda fuera del alcance de toda revisión
porque no forma parte de lo que cada fase entrega.

El decorado de la puesta en marcha sobrevive al estreno.

**Lo que se deriva, y es accionable.** Un inventario de credenciales necesita dos
ejes, no uno: qué credenciales existen **y cuándo se crearon**. El segundo es el
que localiza este patrón. Las credenciales más antiguas de un proyecto son las
que más probablemente contradicen sus decisiones más recientes, y las que menos
probablemente haya mirado alguien.

Aplicado a este enclave, quedan por revisar con ese criterio: el inventario de
almacenes de credenciales del P0-3 —hoy siete, no cuatro—, las claves de servicio
de las fases 1 a 7, y cualquier valor de `.env` anterior a la fase que lo
consume.

---

## 4. Relación con el resto de la documentación

- **RA-1** (`docs/riesgos-aceptados-hook-nivel1.md`) se apoya en D1. El §1 de este
  documento corrige el estado real de D1 en el momento en que RA-1 se escribió.
- **`docs/mejora2-tls-canal-rtty.md`** depende del §2: la mejora era imposible
  antes de corregir el certificado del servidor.
- **`docs/mejora6-endurecimiento-dispositivo.md`** §6 recoge el primer caso desde
  el lado del dispositivo, donde se encontró.
