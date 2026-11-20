# Occupify Observability Dev-to-Prod Test Failure Taxonomy Matrix

## 1. Test Strategy & Quality Gates

This test plan enforces a 4-tier verification matrix ensuring that the Grafana, Alloy, Loki, Tempo, and Prometheus observability stack (developed in `occupify-obs` and deployed at `/opt/occupify-obs` on AWS Web EC2) operates reliably under production conditions, protects host resources on `t3.micro`, and delivers a seamless user experience.

---

## 2. Dev-to-Prod Test Failure Taxonomy Matrix

| Taxonomy Tier | Category / Failure Mode | Test Description & Command | Acceptance Criteria |
|---|---|---|---|
| **Tier 1: Dev / Unit & Logic** | Config Syntax & Parsing | Validate `docker-compose.yml` with `docker compose config` | Exit code 0, zero schema warnings. |
| **Tier 1: Dev / Unit & Logic** | Alloy Configuration Syntax | Validate Alloy syntax against grammar rules | No parse or unknown component errors. |
| **Tier 1: Dev / Unit & Logic** | Loki & Tempo YAML Structure | Inspect YAML indentations, schema v13, and storage blocks | Valid yaml parser output without errors. |
| **Tier 1: Dev / Unit & Logic** | Port Collision Check | Check that ports 3000, 3100, 3200, 4317, 4318, 9090, 9100 are not hijacked by other services | `ss -tulpn` shows clean bindings. |
| **Tier 2: CI / Integration & Contract** | Container Health | Inspect running container states with `docker compose ps` on Web | All central containers in `Up` / `healthy` state. |
| **Tier 2: CI / Integration & Contract** | Multi-Node Agent Health | Inspect node-exporter & promtail on all 6 service nodes | Containers active and running on all 6 nodes. |
| **Tier 2: CI / Integration & Contract** | Prometheus Scrape Target State | Query Prometheus API: `curl -s http://127.0.0.1:9090/api/v1/targets` | All 7 node-exporter targets report `"health": "up"`. |
| **Tier 2: CI / Integration & Contract** | Multi-Service Log Ingestion | Query Loki for log streams: `{service=~"gateway|identity|core|payment|noti|admin|web"}` | Logs actively flowing from all services into Loki. |
| **Tier 2: CI / Integration & Contract** | Loki Log Push API Contract | Push test log entry via POST `http://127.0.0.1:3100/loki/api/v1/push` | Returns HTTP 204 No Content. |
| **Tier 2: CI / Integration & Contract** | Tempo OTLP Ingestion Contract | Send synthetic OTLP span to `127.0.0.1:4318/v1/traces` | Returns HTTP 200/202 Success. |
| **Tier 2: CI / Integration & Contract** | Grafana Datasources Contract | Call Grafana Datasource Health API: `/api/datasources/uid/<uid>/health` | Status returns `"message": "Data source is working"`. |
| **Tier 3: Staging / Parity & Ingress** | Nginx Subpath Routing | Request `curl -sI https://occupify.tienvm.dpdns.org/grafana/` | Returns HTTP 200 or 302 redirect to `/grafana/login`. |
| **Tier 3: Staging / Parity & Ingress** | pgAdmin Ingress & Auth | Request `curl -sI https://occupify.tienvm.dpdns.org/pgadmin/` | Returns HTTP 200 or 302 redirect to login page. |
| **Tier 3: Staging / Parity & Ingress** | Multi-Database Connectivity | Verify pgAdmin connects to all 5 DB hosts (`10.0.10.x:5432`) | Port 5432 open from Web, all 5 DBs reachable. |
| **Tier 3: Staging / Parity & Ingress** | Subpath Asset Integrity | Verify CSS/JS assets requested under `/grafana/public/build/...` | Returns HTTP 200 with appropriate mime types (no 404s). |
| **Tier 3: Staging / Parity & Ingress** | WebSocket Upgrade Header | Test WebSocket handshake on `/grafana/api/live/ws` | Returns HTTP 101 Switching Protocols or valid handshake response. |
| **Tier 3: Staging / Parity & Ingress** | TLS Certificate Validity | Inspect TLS certificate returned by domain | Subject matches `occupify.tienvm.dpdns.org`, not expired. |
| **Tier 4: Prod Reality & Worst-Case** | Memory Starvation & Swap | Check memory consumption under load using `free -h` and `docker stats` | Swap is utilized, RAM available > 200MB, zero OOM kills. |
| **Tier 4: Prod Reality & Worst-Case** | Disk Fill-Up & Log Caps | Verify Docker container log options (`max-size: 10m`, `max-file: 3`) | Container inspect confirms logging configuration. |
| **Tier 4: Prod Reality & Worst-Case** | Reboot Resilience | Ensure `restart: unless-stopped` is declared for all services | Containers survive Docker daemon restart (`systemctl restart docker`). |
| **Tier 4: Prod Reality & Worst-Case** | Trace-to-Log Correlation | Query trace in Tempo, click "Logs for this span" -> verify Loki query displays matching log stream | Exact traceId is correlated across Tempo and Loki. |

---

## 3. Real Persona Simulation Journeys (Stage 5)

### Persona: DevOps & SRE Engineer
1. **Journey 1: Login & Navigation**:
   - Access `https://occupify.tienvm.dpdns.org/grafana/login` via browser.
   - Authenticate with admin credentials.
   - Confirm successful redirect to `/grafana/` home dashboard.
2. **Journey 2: Metrics Exploration**:
   - Open Host System / Node Exporter Dashboard.
   - Verify real-time CPU, Memory, Disk, and Network graphs populate.
3. **Journey 3: Trace & Log Investigation**:
   - Open Explore panel (`/grafana/explore`).
   - Select Tempo datasource, query recent trace spans.
   - Click "Document / Trace" -> click linked Loki button -> confirm corresponding log stream displays instantly.
