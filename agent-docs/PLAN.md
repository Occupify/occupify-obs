# Occupify Observability Stack Implementation Plan

## 1. Plan Overview & Objectives
Deploy a production-grade, low-footprint Observability stack developed in **`occupify-obs`** (`https://github.com/Occupify/occupify-obs.git`) and deployed to AWS Web EC2 (`10.0.1.78`) complying with `architecture.drawio` and user requirements:
- Codebase Location: `occupify-obs` (sibling repository to `occupify-infra`)
- Host Deployment Directory: `/opt/occupify-obs`
- Stack: Grafana, Grafana Alloy, Grafana Loki, Grafana Tempo, Prometheus, Node Exporter
- Reverse-proxied via Nginx at `https://occupify.tienvm.dpdns.org/grafana/`

---

## 2. Work Breakdown Structure (Atomic Tasks)

### Phase 1: Codebase Setup in `occupify-obs`
- **Task 1.1**: Initialize `occupify-obs` project structure:
  ```
  occupify-obs/
  ├── docker-compose.yml             # Central stack on Web EC2 (Grafana, Loki, Tempo, Prometheus, pgAdmin)
  ├── Makefile                       # Lifecycle targets
  ├── README.md                      # Architecture and runbook
  ├── agent/                         # Lightweight forwarder for service nodes
  │   ├── compose.agent.yml          # Node Exporter + Promtail
  │   └── promtail.yaml              # Log scraping & filtering per service
  ├── config/
  │   ├── loki/
  │   │   └── loki.yaml              # Log storage & 7-day retention
  │   ├── tempo/
  │   │   └── tempo.yaml             # Trace storage & OTLP receivers (:4318)
  │   ├── prometheus/
  │   │   └── prometheus.yml         # Scrapes 7 nodes (9100) & microservices (8080)
  │   └── pgadmin/
  │       ├── servers.json           # Auto-discovers 5 PostgreSQL DBs
  │       └── pgadmin-config.py      # SCRIPT_NAME = '/pgadmin'
  ├── grafana/
  │   ├── provisioning/
  │   │   ├── datasources/
  │   │   │   └── datasources.yaml   # Prometheus, Loki, Tempo
  │   │   └── dashboards/
  │   │       └── dashboards.yaml
  │   └── dashboards/
  │       ├── cluster-overview.json  # Multi-node host overview (7 nodes)
  │       ├── logs-explorer.json     # All services logs & search
  │       └── microservices.json     # Spring Boot JVM & HTTP overview
  ├── nginx/
  │   ├── occupify-grafana.conf      # Nginx proxy snippet for /grafana/
  │   └── occupify-pgadmin.conf      # Nginx proxy snippet for /pgadmin/
  └── scripts/
      ├── deploy-web.sh              # Deploys central stack to web EC2
      ├── deploy-agents.sh           # Deploys forwarders to all 6 service nodes
      ├── expose-databases.sh        # Exposes 5432 on the 5 private DB hosts for pgAdmin
      └── verify-all.sh              # End-to-end verification across all nodes
  ```
- **Task 1.2**: Commit and push initial structured release to `occupify-obs` git repository.

### Phase 2: Host Environment & Multi-Resource Preparation
- **Task 2.1**: Verify and persist 3GB Swap file (`/swapfile`) on Web EC2 (`10.0.1.78`).
- **Task 2.2**: Expose PostgreSQL port 5432 on each database node (`identity`, `core`, `payment`, `noti`, `admin`) to the internal VPC (`10.0.0.0/16`).
- **Task 2.3**: Provision `/opt/occupify-obs` on Web EC2 and sync central stack configuration.
- **Task 2.4**: Deploy central stack on Web EC2 (`docker compose up -d`) and configure Nginx reverse proxies for both `/grafana/` and `/pgadmin/`.
- **Task 2.5**: Distribute and run telemetry agents (`compose.agent.yml`) to all 6 service nodes.

### Phase 2: Configuration & Telemetry Pipeline
- **Task 2.1**: Craft `config.alloy`:
  - Receivers: OTLP gRPC (`0.0.0.0:4317`), OTLP HTTP (`0.0.0.0:4318`), Prometheus scrape for Node Exporter (`node_exporter:9100`), Host/Nginx log scrape.
  - Exporters: Traces forward to Tempo (`tempo:4317`), Logs forward to Loki (`http://loki:3100/loki/api/v1/push`), Metrics forward to Prometheus remote-write / scrape.
- **Task 2.2**: Craft `loki.yaml`:
  - Single-binary mode, retention limit 7 days (168h), filesystem storage schema `v13`, compactor enabled.
- **Task 2.3**: Craft `tempo.yaml`:
  - Single-process mode, local block storage, retention 168h, OTLP ingestion on port 4317/4318.
- **Task 2.4**: Craft `prometheus.yml`:
  - Scrape configs for: `node_exporter`, `alloy`, `prometheus`, `loki`, `tempo`.
- **Task 2.5**: Craft Grafana Datasources (`datasources.yaml`):
  - Prometheus (UID: `prometheus`, Default: true, URL: `http://prometheus:9090`)
  - Loki (UID: `loki`, URL: `http://loki:3100`, configured with `derivedFields` mapping TraceID to Tempo)
  - Tempo (UID: `tempo`, URL: `http://tempo:3200`, configured with `tracesToLogs` querying Loki `{service_name=~"$${__service_name}"} |= "$${__trace.id}"`)
- **Task 2.6**: Craft Grafana Dashboards Provisioning (`dashboards.yaml` + pre-built dashboard JSONs for Host/System & Microservice overview).

### Phase 3: Docker Compose Stack Definition
- **Task 3.1**: Define `/opt/occupify-observability/docker-compose.yml`:
  - Services: `grafana`, `alloy`, `loki`, `tempo`, `prometheus`, `node_exporter`.
  - Network: dedicated `observability_net` bridge network.
  - Storage: Named volumes for data persistence (`grafana_data`, `prometheus_data`, `loki_data`, `tempo_data`).
  - Strict resource constraints (`mem_limit` and `cpus` limits per container to safeguard `t3.micro`).
  - Container logging driver with `max-size: 10m` and `max-file: 3`.

### Phase 4: Ingress & TLS Integration
- **Task 4.1**: Update `/etc/nginx/conf.d/occupify-web.conf` on Web EC2:
  - Add `location /grafana/` proxying to `http://127.0.0.1:3000/`.
  - Add WebSocket upgrade headers (`$http_upgrade`, `Connection "upgrade"`).
  - Preserve host headers and forwarded protocol.
- **Task 4.2**: Test Nginx syntax (`sudo nginx -t`) and reload service (`sudo systemctl reload nginx`).

### Phase 5: Multi-Tier Verification & Live Testing (Stages 4 & 5)
- **Task 5.1**: Launch compose stack (`docker compose up -d`).
- **Task 5.2**: Execute Tier 1-4 tests (Datasource health, log ingestion, trace span ingestion, metrics scrape, subpath routing).
- **Task 5.3**: End-user journey simulation (Accessing Grafana UI via HTTPS, exploring logs and traces, validating live queries).

### Phase 6: Production Signoff & Documentation (Stage 6)
- **Task 6.1**: Verify resource stability (`free -h`, `docker stats --no-stream`).
- **Task 6.2**: Document access credentials, endpoint URLs, and architecture alignment.
- **Task 6.3**: Persist `agent-docs/PRODUCTION_READINESS.md` and deliver final summary.
