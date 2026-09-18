#!/usr/bin/env python3
"""Censo de grupos y reglas de alerta a partir de logs de Wazuh.

Lee uno o mas ficheros de alertas de Wazuh en formato JSON-lines (un objeto
JSON por linea) y produce un recuento por agente, por grupo de regla y por
regla individual, ademas de una lista de reglas candidatas a escalada segun
su nivel.

Origen de los ficheros de entrada
----------------------------------
Los logs de alertas de Wazuh viven dentro del contenedor
`single-node-wazuh.manager-1`: el fichero activo en
`/var/ossec/logs/alerts/alerts.json` y los rotados en
`/var/ossec/logs/alerts/<anio>/<mes>/` (algunos comprimidos con gzip). Este
script no los extrae por si mismo: no hace llamadas de red ni invoca
`docker exec`/`docker cp`. Extraer los ficheros del contenedor es un paso
manual deliberado que queda fuera de esta herramienta a proposito -- este
script es de solo lectura y opera exclusivamente sobre ficheros ya copiados
al filesystem local, pasados como argumentos posicionales.

Uso:
    censo-grupos-alertas.py [--nivel-minimo N] FICHERO [FICHERO ...]
"""

import argparse
import gzip
import json
from collections import Counter, defaultdict

SIN_GRUPO = "(sin grupo)"
SIN_AGENTE = "(sin agente)"
SIN_REGLA = "(sin regla)"
SIN_NIVEL = "(sin nivel)"
SIN_DESCRIPCION = "(sin descripcion)"


def abrir(ruta):
    if ruta.endswith(".gz"):
        return gzip.open(ruta, "rt", encoding="utf-8", errors="replace")
    return open(ruta, "r", encoding="utf-8", errors="replace")


def nivel_de(rule):
    crudo = rule.get("level")
    if isinstance(crudo, bool):
        return None
    if isinstance(crudo, int):
        return crudo
    if isinstance(crudo, str):
        try:
            return int(crudo)
        except ValueError:
            return None
    return None


def grupos_de(rule):
    crudo = rule.get("groups")
    if not isinstance(crudo, list) or not crudo:
        return [SIN_GRUPO]
    limpio = [g if isinstance(g, str) and g else SIN_GRUPO for g in crudo]
    return limpio or [SIN_GRUPO]


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Censo de grupos y reglas de alerta a partir de logs de Wazuh "
            "(JSON-lines, planos o .gz)."
        )
    )
    parser.add_argument(
        "ficheros",
        metavar="FICHERO",
        nargs="+",
        help="Fichero de alertas de Wazuh (.json o .json.gz), uno o varios.",
    )
    parser.add_argument(
        "--nivel-minimo",
        type=int,
        default=9,
        dest="nivel_minimo",
        help=(
            "Nivel de regla (rule.level) a partir del cual una regla se "
            "lista como candidata a escalada (por defecto: 9)."
        ),
    )
    args = parser.parse_args()

    total_parsed = 0
    unreadable = 0
    min_ts = None
    max_ts = None

    agent_counts = Counter()

    group_counts = Counter()
    group_max_level = {}

    rule_counts = Counter()
    rule_max_level = {}
    rule_agents = defaultdict(set)
    rule_groups = defaultdict(set)
    rule_description = {}

    for ruta in args.ficheros:
        with abrir(ruta) as f:
            for linea in f:
                linea = linea.strip()
                if not linea:
                    continue
                try:
                    alerta = json.loads(linea)
                except json.JSONDecodeError:
                    unreadable += 1
                    continue
                if not isinstance(alerta, dict):
                    unreadable += 1
                    continue

                total_parsed += 1

                ts = alerta.get("timestamp")
                if isinstance(ts, str) and ts:
                    if min_ts is None or ts < min_ts:
                        min_ts = ts
                    if max_ts is None or ts > max_ts:
                        max_ts = ts

                agent = alerta.get("agent")
                agent_name = None
                if isinstance(agent, dict):
                    agent_name = agent.get("name")
                agent_name = agent_name if isinstance(agent_name, str) and agent_name else SIN_AGENTE
                agent_counts[agent_name] += 1

                rule = alerta.get("rule")
                rule = rule if isinstance(rule, dict) else {}

                rule_id_crudo = rule.get("id")
                rule_id = str(rule_id_crudo) if rule_id_crudo is not None else SIN_REGLA

                level = nivel_de(rule)
                groups = grupos_de(rule)

                descripcion_crudo = rule.get("description")
                descripcion = (
                    descripcion_crudo
                    if isinstance(descripcion_crudo, str) and descripcion_crudo
                    else SIN_DESCRIPCION
                )

                for grupo in groups:
                    group_counts[grupo] += 1
                    if level is not None:
                        actual = group_max_level.get(grupo)
                        if actual is None or level > actual:
                            group_max_level[grupo] = level

                rule_counts[rule_id] += 1
                rule_agents[rule_id].add(agent_name)
                rule_groups[rule_id].update(groups)
                if rule_id not in rule_description:
                    rule_description[rule_id] = descripcion
                if level is not None:
                    actual = rule_max_level.get(rule_id)
                    if actual is None or level > actual:
                        rule_max_level[rule_id] = level

    ancho = 70

    print("=" * ancho)
    print("1. COBERTURA")
    print("=" * ancho)
    print(f"Ficheros leidos:            {len(args.ficheros)}")
    print(f"Alertas parseadas:          {total_parsed}")
    if unreadable > 0:
        print(
            f"Lineas ilegibles (no JSON): {unreadable}  <-- censo potencialmente incompleto"
        )
    else:
        print("Lineas ilegibles (no JSON): 0")
    print(f"Timestamp minimo:           {min_ts if min_ts else '(no encontrado)'}")
    print(f"Timestamp maximo:           {max_ts if max_ts else '(no encontrado)'}")
    print()

    print("=" * ancho)
    print("2. POR AGENTE (agent.name)")
    print("=" * ancho)
    for nombre, n in agent_counts.most_common():
        print(f"{n:>8}  {nombre}")
    print()

    print("=" * ancho)
    print("3. POR GRUPO (rule.groups)")
    print("=" * ancho)
    for grupo, n in group_counts.most_common():
        nivel = group_max_level.get(grupo, SIN_NIVEL)
        print(f"{n:>8}  nivel_max={nivel:<10}  {grupo}")
    print()

    print("=" * ancho)
    print("4. POR REGLA (rule.id)")
    print("=" * ancho)
    for rule_id, n in rule_counts.most_common():
        nivel = rule_max_level.get(rule_id, SIN_NIVEL)
        agentes = ", ".join(sorted(rule_agents[rule_id]))
        grupos = ", ".join(sorted(rule_groups[rule_id]))
        desc = rule_description.get(rule_id, SIN_DESCRIPCION)[:70]
        print(f"{n:>8}  rule.id={rule_id}  nivel={nivel}")
        print(f"          descripcion: {desc}")
        print(f"          agentes:     {agentes}")
        print(f"          grupos:      {grupos}")
    print()

    print("=" * ancho)
    print(f"5. CANDIDATAS A ESCALADA (rule.level >= {args.nivel_minimo})")
    print("=" * ancho)
    candidatas = [
        (rule_id, n)
        for rule_id, n in rule_counts.items()
        if rule_max_level.get(rule_id) is not None
        and rule_max_level[rule_id] >= args.nivel_minimo
    ]
    candidatas.sort(key=lambda item: item[1], reverse=True)
    if not candidatas:
        print("(ninguna regla alcanza el nivel minimo configurado)")
    for rule_id, n in candidatas:
        nivel = rule_max_level.get(rule_id)
        desc = rule_description.get(rule_id, SIN_DESCRIPCION)[:70]
        print(f"{n:>8}  rule.id={rule_id}  nivel={nivel}  {desc}")


if __name__ == "__main__":
    main()
