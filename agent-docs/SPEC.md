# Occupify Observability Stack Specification

## 1. Executive Summary & Architecture Overview

This specification establishes the centralized Observability, Metrics, Logging, and Distributed Tracing stack for Occupify, implementing the architecture outlined in `architecture.drawio` and `architecture.yml`.
The entire codebase and configuration artifacts are housed in the dedicated repository: **`occupify-obs`** (`https://github.com/Occupify/occupify-obs.git`).

### System Topology & Placement
- **Repository Source**: `occupify-obs` (`https://github.com/Occupify/occupify-obs.git`)
- **Central Host Target**: AWS Web EC2 instance (`10.0.1.78` private IP / `13.250.222.125` public IP, `t3.micro`).
- **Telemetry Collection Across All Services**:
  1. **Gateway** (`10.0.10.143`): HTTP ingress routing, request logging, correlation ID propagation.
  2. **Identity** (`10.0.10.62`): Authentication, token lifecycle, Redis session events, PostgreSQL (`occupify_identity`).
  3. **Core** (`10.0.10.146`): Business logic, rental, contract transactions, PostgreSQL (`occupify_core`).
  4. **Payment** (`10.0.10.202`): Financial transaction logs, order webhooks, PostgreSQL (`occupify_payment`).
  5. **Notification** (`10.0.10.86`): RabbitMQ consumer events, email dispatch logs, PostgreSQL (`occupify_noti`).
  6. **Administration** (`10.0.10.103`): Moderation, system config logs, PostgreSQL (`occupify_administration`).
  7. **Web & Nginx** (`10.0.1.78`): Ingress access logs, upstream timing, host metrics.
- **Centralized Database Administration (pgAdmin 4)**:
  - Running on Web EC2 as part of `occupify-obs` stack (`dpage/pgadmin4:8.12`).
  - Securely reverse-proxied at `https://occupify.tienvm.dpdns.org/pgadmin/`.
  - Pre-provisioned `servers.json` auto-loading all 5 PostgreSQL databases across the private subnet (`10.0.10.x:5432`).
- **Ingress & Forwarding Mechanism**:
  - **Metrics**: Prometheus on `web` scrapes all 7 nodes via Node Exporter (`9100`) and Spring Boot Actuators (`8080`) at 15s intervals.
  - **Logs**: Lightweight Promtail agents running on each service node tail container logs from Podman, filter verbose health checks, and push to Loki (`http://10.0.1.78:3100/loki/api/v1/push`).
  - **Traces**: Tempo listens for OTLP on `10.0.1.78:4318` (HTTP) and `4317` (gRPC).
  - **Polling Mode**: Standard HTTP polling enabled; WebSocket overhead disabled for maximum connection stability.
- **Target Deployment Directory**: `/opt/occupify-obs/` on Web EC2, with `/opt/occupify-agent/` on service nodes.
- **Resource Protection**: 3GB Swap on Web EC2; per-container memory limits (150MB–200MB on central stack, 30MB–50MB on node agents) ensuring 0% risk of OOM.
- **Access Ingress**:
  - Grafana: `https://occupify.tienvm.dpdns.org/grafana/`
  - pgAdmin 4: `https://occupify.tienvm.dpdns.org/pgadmin/`

---

## 2. Ingress & Routing Contract

### URL & Subpath Contract
- **Base URL**: `https://occupify.tienvm.dpdns.org/grafana/`
- **Subpath Handling**:
  - `GF_SERVER_ROOT_URL=https://occupify.tienvm.dpdns.org/grafana/`
  - `GF_SERVER_SERVE_FROM_SUB_PATH=true`
- **Nginx Ingress Block**:
  ```nginx
  location /grafana/ {
      proxy_pass http://127.0.0.1:3000;
      proxy_http_version 1.1;
      proxy_set_header Upgrade $http_upgrade;
      proxy_set_header Connection "upgrade";
      proxy_set_header Host $http_host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
  }
  ```

---

## 3. Triad Analysis: Edge Cases, Eval Cases, and Worst Cases

### 3.1 Edge Cases
| ID | Area | Scenario | Expected Resilience Behavior |
|---|---|---|---|
| **EDGE-01** | Subpath URL | Accessing `https://occupify.tienvm.dpdns.org/grafana` without trailing slash | Nginx or Grafana issues clean 301/302 redirect to `/grafana/` preserving path and query parameters without 404. |
| **EDGE-02** | Live Telemetry | WebSocket connection upgrade failure or dropping | Grafana Live falls back gracefully to HTTP long-polling or polling without breaking dashboard UI panels. |
| **EDGE-03** | Tracing | Requests without incoming trace parent headers | Alloy and Tempo generate or accept new root span IDs without rejecting the payload or generating orphan spans. |
| **EDGE-04** | Logs | Extremely long log lines (>64KB) or malformed UTF-8 from services | Loki and Alloy truncate or sanitize lines cleanly without crashing container or dropping subsequent log batches. |
| **EDGE-05** | Actuator Metrics | Target microservices returning 404 or empty `/actuator/prometheus` | Prometheus logs scrape failure, marks target `DOWN`, continues scraping other targets without crashing scrape loops. |

### 3.2 Eval Cases (SLA, Performance & UX)
| ID | Dimension | Metric / Target | Verification Method |
|---|---|---|---|
| **EVAL-01** | UI Responsiveness | Grafana dashboard initial paint < 1.5s; panel query latency p95 < 250ms | Browser DevTools timing & curl TTFB verification. |
| **EVAL-02** | Correlation UX | 1-click navigation from Tempo Trace span -> Loki logs for corresponding TraceID | Grafana `derivedFields` and `tracesToLogs` datasource configuration test. |
| **EVAL-03** | Datasource Health | 100% PASS on Grafana internal datasource test for Prometheus, Loki, and Tempo | `/api/datasources/uid/<uid>/health` HTTP check. |
| **EVAL-04** | Log Latency | Timestamp of log event in container to availability in Grafana Explore < 5s | Ingest test log entry and query via Loki logql within 5s window. |

### 3.3 Worst Cases & Blast Radius Containment
| ID | Threat Vector | Worst-Case Impact | Safeguard & Mitigation |
|---|---|---|---|
| **WORST-01** | Memory Starvation on `t3.micro` | OOM Killer terminates Nginx or production Web service | 1. 3GB Swap space active (`/swapfile`).<br>2. Hard `mem_limit` and `mem_reservation` configured on all compose containers (e.g. 200M–300M max per container). |
| **WORST-02** | Disk Full from Logs / Traces | Root disk (`/dev/root`) exhausted, preventing OS writes | 1. 7-day strict retention on Loki chunks & Tempo blocks.<br>2. Compactor enabled.<br>3. Docker logging driver capped with `max-size: 10m` and `max-file: 3`. |
| **WORST-03** | Ingestion Storm / Network Spike | CPU saturation from high trace/log volume | Alloy in-memory queue with buffer caps and drop policy for non-critical telemetry under backpressure. |
| **WORST-04** | System Reboot | Unmonitored containers remain stopped after host reboot | All services set to `restart: unless-stopped` with systemd Docker service enabled on boot. |

---

## 4. Subagent Delegation Model

| Subagent Role | Skill Adopted | Responsibilities |
|---|---|---|
| **Lead Coordinator** | `my-teams-sdlc` | Orchestrates lifecycle stages, user gates, and feedback synthesis. |
| **Observability Architect** | `observability-and-instrumentation` | Designs and builds Docker Compose definitions, Alloy configurations, Tempo, Loki, and Prometheus setups. |
| **Ingress & Security Hardener** | `security-and-hardening` | Configures Nginx reverse proxy, SSL passthrough, WebSocket upgrades, and credential safeguards. |
| **QA Verification Lead** | `test-engineer` | Executes the 4-tier failure taxonomy test matrix, load checks, and persona simulations. |
