# Fase 8 · Mejora 5 — Prueba mensual de resiliencia del enclave

**Estado:** procedimiento definido, con los modos de fallo medidos en la primera
ejecución (11 de septiembre de 2026).

**Qué es:** una prueba periódica que verifica que las vías de recuperación del
enclave existen cuando sus dependencias caen. No es construcción: es
procedimiento, y su valor está en ejecutarse, no en estar escrita.

---

## 1. Por qué el planteamiento original medía menos de lo que prometía

El README la enunciaba como "prueba mensual con Headscale detenido". Al
ejecutarla por primera vez, el resultado fue que **detener Headscale casi no
rompe nada**.

Tailscale separa plano de control y plano de datos. Los nodos ya registrados
conservan sus claves y rutas, y siguen comunicándose entre sí sin el coordinador.
Medido con Headscale parado:

| Comprobación | Resultado |
|---|---|
| `ping 100.64.0.2` (DC01 por tailnet) | Responde |
| `curl https://100.64.0.1:4833` (IRIS por tailnet) | `302` |

Lo único observable fue una degradación transitoria: latencias de 8-10 s en el
primer ping tras detener el servicio, con pauta descendente de ~1 s por paquete —
una cola drenándose al interrumpirse el relay DERP (Headscale publica 3478/udp).
Estado normal restablecido: 2-3 ms por tailnet, 1,4 ms por LAN.

Una prueba que detiene Headscale y comprueba que todo sigue funcionando pasa
siempre, y no mide nada.

---

## 2. El modo de fallo real

Lo que rompe no es la caída del coordinador, sino **la caída del coordinador más
el reinicio de un nodo**. Al arrancar, el cliente Tailscale necesita el
coordinador para reconstruir su mapa de red.

Medido con DC01:

| Escenario | Resultado |
|---|---|
| Headscale parado, DC01 en marcha | Responde por `100.64.0.2` |
| Headscale parado, **DC01 reiniciado** | **100% de pérdida. Fuera del tailnet** |
| Headscale restablecido | Reconecta, con retraso superior a 30 s |

Ese es el escenario que la prueba mensual debe reproducir.

### 2.1 Consecuencia para la detección del nivel 2

El §8 del reconocimiento delega la detección del `powerreset` del nivel 2 en un
observador independiente: Wazuh en DC01 registrando un apagado inesperado, o la
caída de su heartbeat vista desde el enclave.

**La caída del heartbeat, por sí sola, no discrimina.** Un `powerreset` malicioso
reinicia DC01; si el atacante ha tumbado antes Headscale, el reinicio produce
exactamente la misma señal que una caída del coordinador: ausencia. El observador
es independiente del dispositivo, no del orquestador.

Lo que sí discrimina es el registro local de Wazuh en DC01, porque queda escrito
en el equipo aunque no llegue al enclave hasta que haya red. La detección debe
apoyarse en ese registro y no sólo en la ausencia de señal.

---

## 3. Procedimiento

Ejecución mensual. Requiere ventana con DC01 prescindible. Duración estimada:
20-30 minutos.

Registrar fecha, ejecutor y resultado de cada paso. Un paso sin criterio previo no
es una prueba; los criterios están fijados abajo y no se ajustan durante la
ejecución.

### M1 · Estado de partida

```bash
docker exec headscale headscale nodes list
docker exec headscale headscale preauthkeys list
ping -c 5 100.64.0.2
```

**Aprobado si:** los tres nodos figuran `online`; **ninguna preauthkey es
reutilizable y está vigente**; latencia en milisegundos.

La comprobación de preauthkeys no es rutina: una clave reutilizable permite
incorporar nodos al tailnet sin intervención del operador. Ver
`docs/credenciales-de-arranque.md` §1.

### M2 · Headscale caído, nodos en marcha

```bash
docker stop headscale
sleep 20
ping -c 3 100.64.0.2
curl -sk -o /dev/null -w '%{http_code}\n' https://100.64.0.1:4833
```

**Aprobado si:** DC01 responde e IRIS sirve. El plano de datos debe sobrevivir.

**Fallo significativo:** pérdida de conectividad aquí indicaría que el plano de
datos depende del coordinador, contra lo medido en la primera ejecución.

### M3 · Headscale caído, nodo reiniciado

Con Headscale aún parado, reiniciar DC01 **desde la consola del KVM** — que
funciona porque es LAN y no depende del tailnet.

```bash
ping -c 3 100.64.0.2
```

**Aprobado si:** pérdida del 100%. Es el comportamiento esperado y documentado.

**Fallo significativo:** que responda indicaría que el cliente conserva estado
suficiente para operar sin coordinador, lo que cambiaría el modelo de
dependencia y habría que documentar.

```bash
docker start headscale
sleep 60
ping -c 3 100.64.0.2
```

**Aprobado si:** reconecta. Anotar el tiempo real, que en la primera ejecución
superó los 30 s.

### M4 · n8n caído — el hook falla cerrado

Es la prueba V4 de la mejora 1, reproducida mensualmente.

```bash
docker stop n8n
```

Desde el navegador, con `operador1`: `https://kvm.oob.local/connect/zsb25f8`.

**Aprobado si:** `403`. El hook debe denegar cuando el orquestador no responde.

Y en el mismo acto, la otra mitad:

**Aprobado si:** `https://192.168.0.36` sigue dando la interfaz del GL-RM1.

Sin esta segunda comprobación, RA-1 afirma una vía de emergencia que nadie ha
verificado. Las dos mitades cuentan: el hook cerrado sin vía de emergencia sería
un enclave inaccesible, y la vía de emergencia sin hook cerrado sería el P0-6.

```bash
docker start n8n
```

### M5 · El hook vuelve a aprobar

Con n8n arriba, repetir `/connect/zsb25f8` como `operador1`.

**Aprobado si:** acceso a consola, y `operador2` sigue recibiendo `403`.

Es la contraprueba de M4: un hook que deniega siempre también pasaría M4.

### M6 · Canal rtty con verificación TLS

```bash
echo | openssl s_client -connect 192.168.0.70:5912 2>/dev/null | \
  openssl x509 -noout -subject -issuer -dates
```

**Aprobado si:** el certificado es `glkvm-cloud.oob.local` emitido por la CA del
enclave, y **no está próximo a caducar**. Emitido el 11 de septiembre de 2026 con
825 días de validez: vence en diciembre de 2028.

Y desde la consola del dispositivo:

```sh
grep -c 'oob-rootCA' /etc/kvmd/user/scripts/S01selfCloud
netstat -tnp | grep 5912
```

**Aprobado si:** el script conserva el `-C` y hay conexión `ESTABLISHED`.

Esta comprobación existe porque el cambio vive en un script que una actualización
de firmware podría reponer, igual que `user-hook-url` vive en una plantilla que
una actualización del vendor revertiría.

### M7 · Configuración del hook tras recreación

```bash
docker exec glkvm_cloud grep -c 'user-hook-url' /home/rttys.conf
```

**Aprobado si:** devuelve 1. Es V6 de la mejora 1, reproducida.

---

## 4. Qué hacer con los resultados

Un fallo en M2, M4 o M6 es un control que ha dejado de funcionar y debe tratarse
como incidente, no como anotación.

Un fallo en M3 es un cambio de comportamiento del producto y merece investigarse
antes de darlo por bueno.

Un fallo en M1 sobre preauthkeys significa que alguien ha creado una clave
reutilizable desde la última prueba.

Registrar siempre, aunque todo pase. La serie de resultados es lo que permite
distinguir una degradación progresiva de un fallo puntual — y es lo que hoy no
existe.

---

## 5. Limitaciones de esta prueba

**No cubre el escenario combinado.** Headscale y n8n caídos a la vez, que es el
caso plausible de un incidente real que afecte al host, no se ha medido. M2 a M5
prueban las dependencias por separado.

**No cubre la pérdida del host.** Todo el enclave corre en el mismo Ubuntu. Si
cae, no hay prueba mensual que valga: la vía es el acceso físico y el nivel 2 del
KVM, que es LAN-only.

**Las métricas de continuidad de este laboratorio no son extrapolables.** El
equipo no está permanentemente encendido, de modo que uptime, reconexiones y
tamaño de logs están contaminados por el ciclo de trabajo. Ver
`docs/mejora6-endurecimiento-dispositivo.md` §10.

**El criterio de M3 depende de comportamiento del producto**, no de configuración
propia. Una versión distinta de Tailscale o de Headscale podría cambiarlo. Por eso
M3 tiene criterio de aprobado en ambos sentidos: lo que importa es detectar el
cambio, no que el resultado sea uno concreto.
