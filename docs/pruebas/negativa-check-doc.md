# Prueba negativa — `verify-hosts.sh --check-doc`

## Por qué existe esta prueba

`--check-doc` se ha usado repetidamente para dar por buena una edición del
README (`docs/README-resolucion-nombres.md`) frente a `docs/resolucion-nombres.tsv`,
siempre observando `doc = 0`. Nunca se ha comprobado que el contador **suba**
cuando debe subir. Un control que solo se ha visto pasar no está verificado:
puede estar detectando divergencias reales, o puede estar comparando dos
conjuntos vacíos y devolviendo éxito por accidente. Esta prueba fuerza una
divergencia real y conocida para confirmar cuál de las dos cosas es cierta.

## Mecánica de `check_doc()` (para interpretar el resultado)

`scripts/verify-hosts.sh:137-162`:

1. Extrae de `docs/resolucion-nombres.tsv` las columnas `(host, nombre, ip)` con
   `awk -F'\t'`, saltando comentarios, líneas en blanco y la cabecera; normaliza
   a minúsculas y ordena → fichero temporal `a`.
2. Extrae de la tabla del README las mismas tres columnas con
   `grep -E '^\|[[:space:]]*(ubuntu|w11|dc01)[[:space:]]*\|' "$DOC" | awk -F'|' ...`;
   normaliza a minúsculas y ordena → fichero temporal `b`.
3. `diff -u "$a" "$b"`: si son iguales, `check-doc: ... coinciden`, exit 0. Si no,
   imprime las líneas `<` (solo en el `.tsv`) y `>` (solo en la tabla del README)
   y devuelve exit 1.

**Qué pasaría si el patrón de extracción del README dejara de casar con
ninguna fila:** `b` quedaría vacío, pero `a` seguiría teniendo las ~23 filas del
`.tsv`. `diff` entre un fichero con contenido y uno vacío **no** son iguales:
`diff -u lleno vacio` devuelve 1, no 0. Es decir, ese escenario concreto **sí**
se detecta hoy como divergencia — no es el punto ciego que parecía.

El punto ciego real es más estrecho: `diff -u vacio vacio` sí devuelve 0. Para
que `check-doc` fallara en silencio harían falta **dos** fallos simultáneos e
independientes — que el patrón del README deje de casar *y* que la extracción
del propio `.tsv` también quede vacía (p. ej. el `.tsv` reducido a solo
cabecera/comentarios). Esta prueba no reproduce ese doble fallo (es un montaje
artificial poco representativo); reproduce el caso simple y realista — una fila
que diverge — que es el que de verdad ocurre cuando una edición del README se
queda a medias.

## Criterio de aprobado (declarado antes de ejecutar nada)

- El código de salida de `verify-hosts.sh --check-doc` tras introducir la
  divergencia debe ser **1**, no 0.
- La salida debe mostrar exactamente **una** fila en discrepancia:
  `ubuntu` / `auth.oob.local`, una vez como `<` (valor en el `.tsv`, alterado) y
  una vez como `>` (valor en la tabla del README, sin tocar).
- Si el código de salida sigue siendo 0, o la salida no señala esa fila, el
  instrumento está roto y ninguna verificación anterior hecha con él tiene
  valor — parar ahí y no continuar con la restauración automática sin revisar
  a mano qué ha pasado.

## Procedimiento

Ejecutar desde la raíz del repositorio.

```bash
cd ~/tfm-alerta-temprana-oob
```

### 0. Precondición: el fichero a alterar debe estar limpio

```bash
git diff --stat docs/resolucion-nombres.tsv
```

Debe salir vacío. Si no lo está, parar: hay cambios sin commitear en ese
fichero que el paso de restauración (`git checkout --`) descartaría.

### 1. Introducir la divergencia deliberada

Cambia únicamente la IP de la fila `ubuntu / auth.oob.local` en el `.tsv` (de
`127.0.0.1` a `127.0.0.9`), sin tocar el README:

```bash
awk -F'\t' 'BEGIN{OFS="\t"} $1=="ubuntu" && $2=="auth.oob.local" { $3="127.0.0.9" } { print }' docs/resolucion-nombres.tsv > /tmp/resolucion-nombres.tsv.divergencia && mv /tmp/resolucion-nombres.tsv.divergencia docs/resolucion-nombres.tsv
```

Confirmar que el cambio es el esperado y está aislado a esa fila:

```bash
git diff docs/resolucion-nombres.tsv
```

### 2. Ejecutar el control y registrar contador y código de salida

```bash
bash scripts/verify-hosts.sh --check-doc
echo "codigo de salida: $?"
```

Anotar aquí, a mano, lo que se observe:

- Código de salida obtenido: _______
- ¿Aparece `ubuntu` / `auth.oob.local` como única fila divergente (`<` con
  `127.0.0.9`, `>` con `127.0.0.1`)? _______

### 3. Restaurar el estado original

```bash
git checkout -- docs/resolucion-nombres.tsv
```

### 4. Verificar la restauración

```bash
git diff --stat docs/resolucion-nombres.tsv
```

Debe salir vacío. Si no sale vacío, el fichero no ha vuelto a su estado
original — no dar la prueba por concluida hasta que esta comprobación sea
limpia.

## Resultado

Sin ejecutar: pendiente. Rellenar tras correr el procedimiento:

- Código de salida obtenido en el paso 2: —
- ¿Coincide con el criterio de aprobado (1, con la fila señalada)?: —
- `git diff --stat` del paso 4 vacío: —
