#!/usr/bin/env python3
"""
Occupify Distributed Trace Bridge & Smart Tempo Proxy
1. Bridges Spring Boot correlation-tagged microservice logs from Loki into Tempo OTLP traces.
2. Provides a smart HTTP proxy on port 3201 that transparently normalizes UUIDs with hyphens
   to 32-hex W3C Trace IDs, allowing Grafana to seamlessly trace by BOTH UUID and Hex without error.
"""
import time
import re
import json
import logging
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
import requests
import sys

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("occupify-trace-bridge")

LOKI_URL = "http://localhost:3100"
TEMPO_INGEST_URL = "http://localhost:4318/v1/traces"
TEMPO_BACKEND_URL = "http://localhost:3200"
PROXY_PORT = 3201

CORR_REGEX = re.compile(r'\[Corr-([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\]')
COMPLETED_REGEX = re.compile(r'Completed request: ([A-Z]+) ([^ ]+) -> Route \[([^\]]+)\] with status \[([^\]]+)\] \(elapsed: ([0-9]+)ms\)')
ROUTING_REGEX = re.compile(r'Routing request: ([A-Z]+) ([^ ]+) -> Route \[([^\]]+)\] Target \[([^\]]+)\]')
ERROR_REGEX = re.compile(r'(?:Client|Server) error handling request for \[([^\]]+)\]: Status ([0-9]+)')

processed_correlations = set()

class SmartTempoProxyHandler(BaseHTTPRequestHandler):
    """
    Transparently intercepts Grafana requests to Tempo.
    If the requested trace ID is a hyphenated UUID, normalizes it to 32-hex before querying Tempo.
    """
    def log_message(self, format, *args):
        pass  # keep logs clean

    def do_GET(self):
        path = self.path
        if "/api/traces/" in path:
            prefix, trace_id = path.split("/api/traces/", 1)
            raw_id = trace_id.split("?")[0]
            clean_id = raw_id.replace("-", "").lower()
            suffix = ("?" + trace_id.split("?", 1)[1]) if "?" in trace_id else ""
            path = f"{prefix}/api/traces/{clean_id}{suffix}"

        backend_url = f"{TEMPO_BACKEND_URL}{path}"
        try:
            headers = {k: v for k, v in self.headers.items() if k.lower() != 'host'}
            r = requests.get(backend_url, headers=headers, timeout=10)
            self.send_response(r.status_code)
            for k, v in r.headers.items():
                if k.lower() not in ['transfer-encoding', 'content-length', 'content-encoding']:
                    self.send_header(k, v)
            self.send_header('Content-Length', str(len(r.content)))
            self.end_headers()
            self.wfile.write(r.content)
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(f"Bad Gateway: {e}".encode())

    def do_POST(self):
        backend_url = f"{TEMPO_BACKEND_URL}{self.path}"
        try:
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length) if content_length > 0 else b""
            headers = {k: v for k, v in self.headers.items() if k.lower() != 'host'}
            r = requests.post(backend_url, data=body, headers=headers, timeout=10)
            self.send_response(r.status_code)
            for k, v in r.headers.items():
                if k.lower() not in ['transfer-encoding', 'content-length', 'content-encoding']:
                    self.send_header(k, v)
            self.send_header('Content-Length', str(len(r.content)))
            self.end_headers()
            self.wfile.write(r.content)
        except Exception as e:
            self.send_response(502)
            self.end_headers()
            self.wfile.write(f"Bad Gateway: {e}".encode())

def start_proxy_server():
    server = HTTPServer(("0.0.0.0", PROXY_PORT), SmartTempoProxyHandler)
    logger.info("Smart Tempo Proxy listening on 0.0.0.0:%d", PROXY_PORT)
    server.serve_forever()

def poll_and_bridge():
    global processed_correlations
    if len(processed_correlations) > 20000:
        processed_correlations.clear()

    now_ns = int(time.time() * 1e9)
    start_ns = now_ns - (120 * 1000 * 1000 * 1000)

    try:
        resp = requests.get(
            f"{LOKI_URL}/loki/api/v1/query_range",
            params={
                "query": '{service=~".+"} |~ "Corr-"',
                "start": str(start_ns),
                "limit": 100
            },
            timeout=5
        )
        if resp.status_code != 200:
            return

        results = resp.json().get("data", {}).get("result", [])
        groups = {}
        for stream in results:
            svc = stream.get("stream", {}).get("service", "unknown")
            for ts_ns_str, line in stream.get("values", []):
                m = CORR_REGEX.search(line)
                if not m:
                    continue
                cid = m.group(1).lower()
                if cid in processed_correlations:
                    continue
                if cid not in groups:
                    groups[cid] = []
                groups[cid].append({
                    "service": svc,
                    "ts_ns": int(ts_ns_str),
                    "line": line
                })

        for cid, entries in groups.items():
            trace_id = cid.replace('-', '')
            entries.sort(key=lambda x: x["ts_ns"])

            method = "GET"
            path = "/"
            route = "unknown"
            status = 200
            duration_ms = 10
            target_url = ""
            gateway_entries = [e for e in entries if e["service"] == "gateway"]
            downstream_entries = [e for e in entries if e["service"] != "gateway"]

            if not gateway_entries and not downstream_entries:
                continue

            start_ts = entries[0]["ts_ns"]
            end_ts = entries[-1]["ts_ns"]

            for e in gateway_entries:
                line = e["line"]
                m_route = ROUTING_REGEX.search(line)
                if m_route:
                    method = m_route.group(1)
                    path = m_route.group(2)
                    route = m_route.group(3)
                    target_url = m_route.group(4)

                m_comp = COMPLETED_REGEX.search(line)
                if m_comp:
                    method = m_comp.group(1)
                    path = m_comp.group(2)
                    route = m_comp.group(3)
                    st_str = m_comp.group(4).split()[0]
                    status = int(st_str) if st_str.isdigit() else 200
                    duration_ms = max(int(m_comp.group(5)), 1)
                    end_ts = e["ts_ns"]
                    start_ts = end_ts - (duration_ms * 1000 * 1000)

                m_err = ERROR_REGEX.search(line)
                if m_err:
                    path = m_err.group(1)
                    status = int(m_err.group(2))
                    route = "gateway-error"

            root_span_id = trace_id[:16]
            if end_ts <= start_ts:
                end_ts = start_ts + (duration_ms * 1000 * 1000)

            root_span = {
                "traceId": trace_id,
                "spanId": root_span_id,
                "name": f"{method} {path}",
                "kind": 2,  # SERVER
                "startTimeUnixNano": str(start_ts),
                "endTimeUnixNano": str(end_ts),
                "attributes": [
                    {"key": "http.method", "value": {"stringValue": method}},
                    {"key": "http.target", "value": {"stringValue": path}},
                    {"key": "http.route", "value": {"stringValue": route}},
                    {"key": "http.status_code", "value": {"intValue": status}},
                    {"key": "correlation.id", "value": {"stringValue": cid}}
                ],
                "status": {
                    "code": 1 if status < 400 else 2,
                    "message": "OK" if status < 400 else f"HTTP {status}"
                }
            }

            resource_spans = [
                {
                    "resource": {
                        "attributes": [
                            {"key": "service.name", "value": {"stringValue": "occupify-gateway"}}
                        ]
                    },
                    "scopeSpans": [{
                        "scope": {"name": "occupify-trace-bridge"},
                        "spans": [root_span]
                    }]
                }
            ]

            downstream_by_service = {}
            for de in downstream_entries:
                svc = de["service"]
                if svc not in downstream_by_service:
                    downstream_by_service[svc] = []
                downstream_by_service[svc].append(de)

            span_counter = 1
            for svc, sv_entries in downstream_by_service.items():
                svc_start = sv_entries[0]["ts_ns"]
                svc_end = sv_entries[-1]["ts_ns"]
                if svc_end <= svc_start:
                    svc_end = svc_start + (5 * 1000 * 1000)

                child_span_id = f"{trace_id[8:16]}{span_counter:08x}"[:16]
                span_counter += 1

                child_span = {
                    "traceId": trace_id,
                    "spanId": child_span_id,
                    "parentSpanId": root_span_id,
                    "name": f"{svc}: handle request",
                    "kind": 1,  # INTERNAL
                    "startTimeUnixNano": str(svc_start),
                    "endTimeUnixNano": str(svc_end),
                    "attributes": [
                        {"key": "service.name", "value": {"stringValue": f"occupify-{svc}"}},
                        {"key": "correlation.id", "value": {"stringValue": cid}},
                        {"key": "log.messages_count", "value": {"intValue": len(sv_entries)}}
                    ],
                    "status": {"code": 1, "message": "OK"}
                }

                resource_spans.append({
                    "resource": {
                        "attributes": [
                            {"key": "service.name", "value": {"stringValue": f"occupify-{svc}"}}
                        ]
                    },
                    "scopeSpans": [{
                        "scope": {"name": "occupify-trace-bridge"},
                        "spans": [child_span]
                    }]
                })

            otlp_payload = {"resourceSpans": resource_spans}
            r = requests.post(TEMPO_INGEST_URL, json=otlp_payload, timeout=2)
            if r.status_code == 200:
                processed_correlations.add(cid)

    except Exception as exc:
        logger.debug("Bridge loop exception: %s", exc)

if __name__ == "__main__":
    # Start smart proxy in background thread
    proxy_thread = threading.Thread(target=start_proxy_server, daemon=True)
    proxy_thread.start()

    if "--once" in sys.argv:
        poll_and_bridge()
        logger.info("Single bridge cycle executed.")
    else:
        logger.info("Occupify Trace Bridge started. Bridging Loki -> Tempo...")
        while True:
            poll_and_bridge()
            time.sleep(3)
