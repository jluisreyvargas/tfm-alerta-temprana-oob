# Fase 8 · Mejora 4 — Consola por subdominio

**Estado:** analizada, **no implementada**, con recomendación razonada. El
análisis encontró un argumento de seguridad que el enunciado original no
contemplaba, y aun así la conclusión es no construirla en este despliegue.

---

## 1. El enunciado original y lo que resultó ser

El README la planteaba como comodidad de operación: servir cada dispositivo en su
propio subdominio en lugar de distinguirlos por ruta. Se clasificó como la única
mejora que no cierra ningún riesgo.

Al examinar las URLs reales apareció otra cosa. Hoy, las dos vías de acceso a un
dispositivo comparten origen:

```
consola:         https://kvm.oob.local/#/rtty/zsb25f8
control remoto:  https://kvm.oob.local/web/zsb25f8/https/127.0.0.1%3A443%2F
```

La segunda es `httpProxyRedirect` sirviendo **la web UI del propio GL-RM1** dentro
del origen `https://kvm.oob.local`. Es decir: el JavaScript de la interfaz del
dispositivo se ejecuta con el mismo origen que la consola de rttys, con acceso a
su `localStorage`, a las cookies accesibles por script y al DOM de la aplicación.

El dispositivo es, por diseño del enclave, la pieza de terceros que no se
considera confiable: fijada por digest, con firmware del fabricante, con `-x` en
su canal hasta la mejora 2. Servir su interfaz en el mismo origen que la
plataforma de gestión es un problema de aislamiento, no de comodidad.

**Un subdominio por dispositivo (`zsb25f8.kvm.oob.local`) le daría origen propio**,
y la política del mismo origen del navegador haría el resto.

---

## 2. Por qué no se implementa

### 2.1 El riesgo es hipotético en este despliegue

El laboratorio tiene **un solo KVM**. Con un dispositivo, el aislamiento de
origen no separa nada: no hay un segundo dispositivo cuya sesión proteger. El
problema aparece con dos o más, cuando la interfaz de uno comprometido podría
alcanzar las sesiones de los otros.

Como diseño para un despliegue con varios dispositivos, el argumento es válido y
queda registrado aquí. Como trabajo pendiente de este TFM, no.

### 2.2 El coste es alto y toca varias capas

**Certificado.** El comodín `*.oob.local` no cubre `zsb25f8.kvm.oob.local`: un
comodín cubre un solo nivel. Habría que reemitir el certificado del enclave con
`SAN *.kvm.oob.local`, o emitir uno por dispositivo.

**Enrutado de cliente.** La consola usa `https://kvm.oob.local/#/rtty/zsb25f8`: el
fragmento `#` no se envía al servidor, de modo que el enrutado lo hace la SPA
después de cargar en la raíz. Servir por subdominio exige que rttys entregue la
SPA en cada nombre y que el WebSocket conecte al nombre correspondiente. No es
configuración: es comportamiento del producto.

**Validación de Host.** `api.go:185` aplica un middleware que valida el Host
contra `cfg.WebUIHost` mediante `proxy.DomainAllowed(host, allowedHost)`. Hoy la
clave está ausente —lo documentó el reconocimiento (§2.4)— y el middleware no
actúa. Con subdominios habría que configurarla y averiguar primero qué acepta esa
función, que por el nombre podría admitir subdominios pero no está verificado.

**Traefik.** Una regla por dispositivo, o una regla con `HostRegexp`, más el
certificado correspondiente.

Cuatro capas para un beneficio que este despliegue no materializa.

### 2.3 Hay trabajo pendiente que sí cierra funcionalidad

La aprobación de segunda persona para `/cmd/` y `/web/` está diseñada (F8-D5) y
no construida: ambas acciones deniegan incondicionalmente. Eso es funcionalidad
prometida en el diseño del hook y ausente, frente a un aislamiento que hoy no
separa nada.

---

## 3. Lo que sí queda como hallazgo

**El control remoto sirve la interfaz del dispositivo en el origen de la
plataforma.** Es una consecuencia del diseño de `/web/:devid/:proto/:addr/*path`
de rttys, no de la configuración del enclave, y no es corregible sin el
subdominio.

Su alcance real hoy está acotado por tres cosas:

- **Un solo dispositivo.** No hay sesión ajena que alcanzar.
- **El hook deniega `/web/` por completo** mientras la aprobación de segunda
  persona no exista. La vía está cerrada, no sólo acotada.
- **`X-Original-URL` de `/web/` trae el destino completo** (`proto` y `addr`), de
  modo que cuando se construya la aprobación, la política puede decidir por
  destino y no sólo por dispositivo — restringir el proxy a `127.0.0.1:443` es
  distinto de permitir cualquier dirección alcanzable desde el KVM.

**Condición de reevaluación.** Si el enclave incorpora un segundo dispositivo KVM,
esta mejora deja de ser hipotética y debe implementarse antes de habilitar
`/web/` para ambos.

---

## 4. Nota sobre el método

Esta mejora estaba clasificada como comodidad de operación desde el hilo
anterior, y la clasificación venía del enunciado, no de haber mirado el sistema.
Bastó pedir las URLs reales para que apareciera el argumento de seguridad.

No cambia la decisión —sigue sin implementarse— pero sí la razón: no se descarta
por ser cosmética, sino por ser un control correcto para un problema que este
despliegue no tiene. La diferencia importa si alguien retoma el proyecto con más
dispositivos.
