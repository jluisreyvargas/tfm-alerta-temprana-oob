# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

TFM ("Trabajo Fin de Máster") thesis project: a self-hosted, **Out-of-Band (OOB)** incident-response
platform that stays operational even when the corporate network/AD is assumed compromised. It wires
together Wazuh (detection), n8n (orchestration), an LLM-based triage agent (LangGraph + Ollama), Rocket.Chat
(war rooms), DFIR-IRIS (case management), Velociraptor (forensic collection), MinIO (evidence store),
Tailscale/Headscale + a Windows agent (break-glass remote access to domain controllers), and OpenSearch
(observability). Everything is Docker Compose per phase, connected over one shared external Docker network.

The repo is organized as sequential phases (`fase1`…`fase8`), each independently deployable and each with
its own `README.md` containing the authoritative setup/validation steps for that phase — **read the phase
README before changing anything in that folder**. The root `README.md` has the overall architecture diagram
and phase index (in Spanish).

## Repository structure (by phase)

| Folder | Role | What's actually inside |
|---|---|---|
| `fase1-infraestructura/` | Base infra | Traefik reverse proxy, Portainer, Authelia (MFA), MongoDB, and a **vendored upstream Wazuh** deployment (`wazuh/` is the full wazuh-docker project, not custom code) |
| `fase2-orquestador/` | Orchestration | **n8n** (workflow automation — the real orchestrator; workflows live inside n8n's own data volume, not as files in this repo) + a bare Ollama compose file |
| `fase3-agentic/` | AI triage | Custom FastAPI + LangGraph service (`app/`) — the actual Python code to edit for agent logic |
| `fase4-breakglass-dc/` | Remote access to DCs | Headscale (self-hosted Tailscale control server), RustDesk server, a Python FastAPI agent (`dcagent/agent_dc.py`) meant to run as a Windows service on domain controllers, and PowerShell response scripts (`scripts/*.ps1`) |
| `fase5-orchestrator-api/` | Forensic collection API | Small custom FastAPI service (`main.py`) called by n8n to validate a collection profile and persist manifest/sha256 metadata to MinIO |
| `fase5-velociraptor/` | Forensic collection engine | Velociraptor server config, collection profiles, MinIO bucket init |
| `fase6-iris/` | Case management | **Vendored upstream DFIR-IRIS** source tree (has its own `CODESTYLE.md`/`CONTRIBUTING.md`) — not custom project code |
| `fase7-observabilidad/` | Metrics | `shared/metrics_client.py`, a dependency-free client that other Python services import to push events to an OpenSearch index (`tfm-metrics-events`) |
| `fase8-kvm/` | Physical fallback | GL.iNet KVM ("Plan C") integration when RustDesk fails |
| `misp/` | Threat intel | Vendored `misp-docker` for self-hosted MISP (CTI source for the triage agent) |
| `docs/` | Thesis proposals & phase-specific docs referenced from READMEs | |

**Important:** the root README's stack table describes the orchestrator as "FastAPI + PostgreSQL + Redis",
but the folder that actually implements orchestration (`fase2-orquestador/`) only contains n8n + Ollama
compose files — orchestration logic lives as n8n workflows, not as Python source in this repo. Do not go
looking for a FastAPI orchestrator app under `fase2-orquestador/`.

## Architecture / data flow

1. Wazuh agents on corporate endpoints report to the Wazuh server (`fase1`).
2. Wazuh sends an alert webhook into n8n (`fase2`), which correlates/dedupes and drives the rest of the flow.
3. n8n calls the LangGraph triage service (`fase3`, `POST /triage`) which scores severity, maps MITRE
   ATT&CK tactic/technique, and recommends a Velociraptor collection profile — see `fase3-agentic/app/graph.py`
   (two-node LangGraph: `triage_agent` → `remediation_agent`, defined in `app/agents.py`/`app/tools.py`).
4. n8n creates/updates a Rocket.Chat War Room and a DFIR-IRIS case (`fase6`) for the incident.
5. For forensic collection, n8n calls the Orchestrator API (`fase5-orchestrator-api`, `POST /velociraptor/collect`),
   which validates the requested profile against the `ALLOWED` allowlist in `main.py`, then drives Velociraptor
   (`fase5-velociraptor`) and writes `manifest.json` + `sha256.txt` to MinIO at
   `s3://{bucket}/{incident_id}/{host}/{timestamp}/`.
6. Sensitive actions (blocking, break-glass access) require human approval from the War Room before execution.
7. Break-glass access to a domain controller goes through Tailscale (via self-hosted Headscale, `fase4`) to a
   Python agent (`agent_dc.py`) running on the DC, which only executes scripts on its `ALLOWED_SCRIPTS`
   allowlist and requires a bearer token (`AGENT_TOKEN` env var) — extending what that agent can run means
   adding both the `.ps1` script under `scripts/` **and** the allowlist entry in `agent_dc.py`.
8. If RustDesk break-glass fails, Plan C falls back to a physical GL.iNet KVM (`fase8`), which requires
   two-person approval for disruptive actions like power resets.
9. All services optionally emit events to OpenSearch via `fase7-observabilidad/shared/metrics_client.py`
   (`log_event(event_type, **fields)` — swallows its own errors so metrics never block the main flow); Python
   services that use it `sys.path.append("/app/shared")` at import time and expect that shared folder mounted
   into their container (see `fase3-agentic/app/main.py`, `fase5-orchestrator-api/main.py`).

Networking: all services join one external Docker network (`oob-network`, created once in `fase1`) and are
fronted by Traefik with `*.oob.local` hostnames (e.g. `n8n.oob.local`) — check `/etc/hosts` requirements in
the relevant phase README before assuming a service is reachable.

## Working in this repo

- There is no repo-wide build/lint/test tooling — each phase is an independent Docker Compose stack with its
  own Python service(s). Treat `fase3-agentic/` and `fase5-orchestrator-api/` as the two places with real,
  editable application code; other phase folders are mostly config plus (for `fase1/wazuh` and `fase6-iris`)
  vendored upstream projects — check their own docs/CONTRIBUTING before modifying vendored code directly.
- Standard workflow per phase: `docker compose up -d` from inside the phase folder (or a subfolder like
  `fase2-orquestador/n8n/`), then `docker compose ps` / `curl` the service's `/health` endpoint. Follow the
  specific phase README for prerequisites (network must exist, `.env` values, `/etc/hosts` entries).
- No automated test suite exists for the custom services; validation is manual via the `curl` examples in
  each phase README (e.g. `fase3-agentic/README.md` has a worked `POST /triage` example).
- Python services are minimal FastAPI apps on Python 3.11-slim, each with its own `requirements.txt` — there
  is no shared virtualenv or dependency management across phases.
- Secrets/config live in per-phase `.env` files (some are committed, e.g. `fase1-infraestructura/.env`,
  `fase5-velociraptor/.env`, `fase6-iris/.env`) rather than `.env.example` alone — check the existing `.env`
  in a phase folder before assuming values need to be invented.
