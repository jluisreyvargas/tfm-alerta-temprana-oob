> **Estado a 2026-09-13 — CERRADO, documento conservado como registro.**
>
> El P0-6 fue remediado el 2026-09-11 por el commit `a214052` («Fase 8 · mejora 1:
> hook de autorización del nivel 1»), con verificación por comportamiento
> documentada en [`cierre-mejora1-hook.md`](cierre-mejora1-hook.md). La condición 1
> de este documento exigía la misma prueba que descubrió el defecto, y el cierre la
> registra invertida: `operador2` sin grupo, `GET /connect/zsb25f8` → `403` donde
> antes había `302`. El cierre añade dos criterios que este documento no exigía:
> que `admin` acceda por intersección de grupos y no por exención (V3), y el
> comportamiento del control con n8n detenido (V4). Los riesgos residuales
> aceptados están en [`riesgos-aceptados-hook-nivel1.md`](riesgos-aceptados-hook-nivel1.md).
>
> La condición 3 —abordar la Mejora 1 después de la Fase E— quedó superada: se
> abordó antes, con la Fase C a medias. La condición 4 no llegó a activarse: el
> GL-RM1 no volvió a estar en línea antes de que el hook estuviera construido.
>
> **Este documento se versiona el 2026-09-13, después de su propio cierre.** No
> estuvo en el repositorio mientras la decisión estaba vigente, del 9 al 11 de
> septiembre: existió solo como fichero local. Se incorpora sin modificar el
> cuerpo, porque el registro de que hubo una decisión deliberada y bajo qué
> condiciones es exactamente lo que su sección final reclama como valor. Que
> faltara es, por sí mismo, una instancia del patrón que documenta.

---

# Decisión — Continuar la Fase C del P1-1a con el P0-6 abierto

**Fecha:** 2026-09-09
**Decide:** Jose Luis Rey
**Afecta a:** secuenciación de `PLAN-P1-1a-borde-tls.md` (Fase C) y a la Mejora 1 de la Fase 8

---

## Qué se decide

Continuar con la Fase C del P1-1a —poner Velociraptor GUI, DFIR-IRIS, MISP, el dashboard de
Wazuh y el dashboard de Traefik detrás del borde TLS con Authelia— mientras el **P0-6
permanece abierto**.

Esto se aparta del criterio seguido hasta ahora en el proyecto, que ha sido cerrar los P0
antes de abordar los P1. Se documenta expresamente por esa razón.

---

## Qué es el P0-6

Verificado por comportamiento en `docs/api-reconocimiento-fase8.md`, con una sesión de
`operador1` (rol `user`, sin grupo de dispositivos asignado):

```
GET /api/devices        →  {"ok":true, ..., "total": 0}
GET /connect/zsb25f8    →  302  https://kvm.oob.local/rtty/zsb25f8
```

La ruta que consulta el modelo de autorización responde que no hay dispositivos visibles. La
ruta que da acceso redirige a la consola. Acceso confirmado hasta shell en el GL-RM1 desde una
ventana privada.

`ListDevices` (`internal/http/handler/device.go:38`) aplica un filtrado correcto por grupos.
Ese control existe y funciona. Simplemente **no se consulta** en `/connect/:devid`,
`/cmd/:devid` ni `/web/:devid/...`.

**Se compone con la exclusión del KVM de Authelia** (F4, sección de Excepciones del README de
resolución de nombres): la única UI del enclave excluida del SSO es precisamente aquella cuya
autenticación propia no gobierna el acceso a los dispositivos. Las dos decisiones son
razonables por separado y su composición no lo es.

---

## Por qué se pospone

- El diseño de la remediación está cerrado (`docs/diseno-hook-autorizacion.md`), pendiente de
  construcción. No es un P0 sin plan: es un P0 con plan y sin ejecutar.
- La superficie expuesta requiere una sesión autenticada en rttys. No es acceso anónimo.
- El dispositivo GL-RM1 está **offline desde 2026-07-13**, lo que limita el alcance práctico
  hoy —pero no lo elimina como defecto, ni lo hará cuando el dispositivo vuelva.
- La Fase C tiene el patrón ya validado con el piloto de MinIO y avanza rápido; interrumpirla
  a medias deja servicios con router y con puerto directo abierto a la vez, que es el estado
  que el propio plan identifica como el peor de los tres posibles (sección 6: «un servicio
  proxificado con la puerta de atrás abierta es equivalente a uno no proxificado, con el
  agravante de que parece protegido»).

---

## Condiciones que se aceptan

1. **El P0-6 no se cierra ni se reclasifica.** Sigue siendo P0 hasta que el hook de
   autorización esté construido y verificado por comportamiento, con la misma prueba que lo
   descubrió: sesión sin grupo asignado, `GET /connect/:devid`, y comprobación de que ya no
   redirige.
2. **La Fase C no altera nada del KVM.** El router `kvm@docker` conserva `secure-headers@file`
   sin Authelia, y no se toca su compose.
3. **La Mejora 1 de la Fase 8 se aborda inmediatamente después de la Fase E**, antes que el
   P1-1b, el P1-1c y el resto del backlog de endurecimiento.
4. **Si el GL-RM1 vuelve a estar en línea antes de que el hook esté construido**, se revisa
   esta decisión: el defecto pasa de teórico a explotable en ese momento.

---

## Aportación al TFM

Un P0 conocido, documentado, con remediación diseñada y expresamente pospuesto es una decisión
de gestión de riesgo defendible. Un P0 que simplemente no se atendió es un hallazgo de
auditoría.

La diferencia entre ambos no está en el estado del sistema —que es idéntico— sino en la
existencia de este documento. Es la misma distinción que el proyecto viene aplicando a los
controles: lo que separa una asimetría deliberada de un olvido es que esté escrita, con su
fecha, sus condiciones y su criterio de revisión.
