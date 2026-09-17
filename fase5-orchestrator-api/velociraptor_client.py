"""Cliente gRPC de Velociraptor para el orchestrator.

Lanza una coleccion contra un cliente, espera a que termine, genera el ZIP de
descarga y devuelve la ruta del fichero en el volumen compartido. El hashing y
la subida a MinIO los hace el caller sobre los bytes reales del fichero.
"""
import json
import os
import time
import logging

import grpc
import yaml
from pyvelociraptor import api_pb2, api_pb2_grpc

logger = logging.getLogger(__name__)

API_CONFIG = os.getenv("VELOCIRAPTOR_API_CONFIG", "/app/api_client.yaml")
DOWNLOADS_DIR = os.getenv("VELOCIRAPTOR_DOWNLOADS", "/velociraptor-downloads")
POLL_INTERVAL = 3
DEFAULT_TIMEOUT = 300


class NoClientError(Exception):
    """El host no tiene ningun cliente Velociraptor registrado."""


class CollectionTimeout(Exception):
    """La coleccion se lanzo pero no termino dentro del timeout."""
    def __init__(self, flow_id, client_id):
        self.flow_id = flow_id
        self.client_id = client_id
        super().__init__(f"timeout: flow {flow_id} en cliente {client_id}")


class CollectionError(Exception):
    """La coleccion termino en estado ERROR."""


def _load_stub():
    cfg = yaml.safe_load(open(API_CONFIG))
    creds = grpc.ssl_channel_credentials(
        root_certificates=cfg["ca_certificate"].encode(),
        private_key=cfg["client_private_key"].encode(),
        certificate_chain=cfg["client_cert"].encode(),
    )
    opts = (("grpc.ssl_target_name_override", "VelociraptorServer"),)
    channel = grpc.secure_channel(cfg["api_connection_string"], creds, opts)
    return api_pb2_grpc.APIStub(channel)


def _vql(stub, query):
    out = []
    req = api_pb2.VQLCollectorArgs(
        Query=[api_pb2.VQLRequest(Name="q", VQL=query)]
    )
    for r in stub.Query(req):
        if r.Response:
            out += json.loads(r.Response)
    return out


def _escape(s):
    # Los identificadores ya vienen validados por CollectRequest (pattern
    # ^[A-Za-z0-9._-]{1,64}$), asi que no pueden contener comillas. Esta
    # funcion es defensa en profundidad por si el origen cambiara.
    return str(s).replace("'", "")


def resolve_client(stub, host):
    """host -> client_id, case-insensitive. El hostname de Velociraptor viene
    en mayusculas (DC01-TFM) y el host de Wazuh puede diferir en caja."""
    host = _escape(host)
    rows = _vql(
        stub,
        "SELECT client_id, os_info.hostname AS host, os_info.system AS os "
        "FROM clients()",
    )
    matches = [r for r in rows if str(r.get("host", "")).lower() == host.lower()]
    if not matches:
        raise NoClientError(host)
    # El mas recientemente visto, si hubiera varios con el mismo hostname.
    matches.sort(key=lambda r: r.get("last_seen_at", 0), reverse=True)
    return matches[0]["client_id"], matches[0].get("os", "unknown")


def collect(host, artifacts, timeout=DEFAULT_TIMEOUT):
    """Lanza la coleccion, espera, genera el ZIP y devuelve metadatos + ruta
    local del fichero en el volumen compartido.

    Devuelve dict: client_id, client_os, flow_id, started_at, ended_at,
    total_rows, zip_local_path, zip_fs_path.
    Lanza NoClientError / CollectionTimeout / CollectionError.
    """
    stub = _load_stub()
    client_id, client_os = resolve_client(stub, host)

    art_list = ", ".join("'%s'" % _escape(a) for a in artifacts)
    started = time.time()
    r = _vql(
        stub,
        "SELECT collect_client(client_id='%s', artifacts=[%s]) AS c "
        "FROM scope()" % (client_id, art_list),
    )
    flow_id = r[0]["c"]["flow_id"]
    logger.info("coleccion lanzada: flow=%s cliente=%s host=%s",
                flow_id, client_id, host)

    # Sondeo hasta FINISHED / ERROR o timeout.
    t0 = time.time()
    state = None
    rows = 0
    while time.time() - t0 < timeout:
        st = _vql(
            stub,
            "SELECT state, total_collected_rows AS rows "
            "FROM flows(client_id='%s', flow_id='%s')" % (client_id, flow_id),
        )
        if st:
            state = st[0].get("state")
            rows = st[0].get("rows") or 0
            if state in ("FINISHED", "ERROR"):
                break
        time.sleep(POLL_INTERVAL)

    if state == "ERROR":
        raise CollectionError("flow %s termino en ERROR" % flow_id)
    if state != "FINISHED":
        raise CollectionTimeout(flow_id, client_id)

    ended = time.time()

    # Generar el ZIP de descarga (bloquea hasta que esta listo).
    dl = _vql(
        stub,
        "SELECT create_flow_download(client_id='%s', flow_id='%s', wait=TRUE) "
        "AS path FROM scope()" % (client_id, flow_id),
    )
    fs_path = dl[0]["path"]  # p.ej. fs:/downloads/C.xxx/F.xxx/archivo.zip

    # Traducir la ruta del filestore a la ruta del volumen compartido.
    # fs:/downloads/... -> {DOWNLOADS_DIR}/...
    if not fs_path.startswith("fs:/downloads/"):
        raise CollectionError(
            "ruta de descarga inesperada: %r" % fs_path)
    rel = fs_path[len("fs:/downloads/"):]
    local_path = os.path.join(DOWNLOADS_DIR, rel)

    # Guarda: el fichero debe existir antes de que el caller lo hashee.
    # Si no existe, el volumen no esta bien montado o la ruta no coincide;
    # es un fallo ruidoso, no un ZIP vacio subido en silencio.
    if not os.path.isfile(local_path):
        raise CollectionError(
            "ZIP no encontrado en el volumen compartido: %s "
            "(fs_path=%s)" % (local_path, fs_path))

    return {
        "client_id": client_id,
        "client_os": client_os,
        "flow_id": flow_id,
        "started_at": int(started),
        "ended_at": int(ended),
        "total_rows": rows,
        "zip_local_path": local_path,
        "zip_fs_path": fs_path,
    }