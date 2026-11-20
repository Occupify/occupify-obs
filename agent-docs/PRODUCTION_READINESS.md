# Occupify Observability & Multi-Database Administration Production Readiness

## 1. System Signoff & Delivery Overview

The Centralized Observability (Grafana, Prometheus, Loki, Tempo) and Multi-Database Administration (pgAdmin 4) stack has been deployed to production on **AWS Web EC2 (`10.0.1.78`)**, developed in the dedicated repository **`occupify-obs`**, and exposed securely via Nginx over HTTPS.

---

## 2. Production Access URLs & Credentials

| Service | Public Access URL | Credentials |
|---|---|---|
| **Grafana Observability** | `https://occupify.tienvm.dpdns.org/grafana/` | **User**: `admin`<br>**Password**: `occ123!@#` |
| **pgAdmin 4 Database Admin** | `https://occupify.tienvm.dpdns.org/pgadmin/` | **Email**: `admin@occupify.vn`<br>**Password**: `occ123!@#` |

---

## 3. Connected Databases in pgAdmin 4

All 5 microservice databases are exposed on internal port `5432` within the private AWS VPC (`10.0.0.0/16`) and pre-configured in pgAdmin's server tree:

| Server Name | Host IP | Port | Database Name | Username | Table Count |
|---|---|---|---|---|---|
| **Occupify Identity DB** | `10.0.10.62` | `5432` | `occupify_identity` | `postgres` | 10 tables |
| **Occupify Core DB** | `10.0.10.146` | `5432` | `occupify_core` | `postgres` | 16 tables |
| **Occupify Payment DB** | `10.0.10.202` | `5432` | `occupify_payment` | `postgres` | 5 tables |
| **Occupify Notification DB** | `10.0.10.86` | `5432` | `occupify_noti` | `postgres` | 3 tables |
| **Occupify Administration DB** | `10.0.10.103` | `5432` | `occupify_administration` | `postgres` | 9 tables |

---

## 4. Telemetry Pipelines & Pre-Provisioned Dashboards

1. **Host Metrics (7 Nodes)**:
   - Node Exporters active on `web`, `gateway`, `identity`, `core`, `payment`, `noti`, `admin` (`:9100`).
   - Scraped every 15s by Prometheus.
   - Dashboard: **"Occupify Cluster Infrastructure Overview"** (`/grafana/d/occupify-cluster-overview/occupify-cluster-infrastructure-overview`).
2. **Container Logs (All Services)**:
   - Promtail agents tail systemd journal for container logs on all 6 nodes, filter noise, and push to Loki (`:3100`).
   - Streams active for: `gateway`, `identity`, `core`, `payment`, `noti`, `administration`.
   - Dashboard: **"Occupify Unified Log Explorer"** (`/grafana/d/occupify-log-explorer/occupify-unified-log-explorer`).
3. **Distributed Tracing (Tempo)**:
   - OTLP HTTP receiver (`:4318`), OTLP gRPC (`:4317`), Zipkin (`:9411`).
   - 1-click Trace-to-Log navigation configured between Tempo and Loki using Correlation IDs (`Corr-<uuid>`).

---

## 5. Host Resource Profile & Stability Safeguards

- **Total Memory Footprint on Web EC2 (`t3.micro`)**:
  - `occupify-pgadmin`: ~69 MiB
  - `occupify-grafana`: ~56 MiB
  - `occupify-loki`: ~45 MiB
  - `occupify-prometheus`: ~28 MiB
  - `occupify-tempo`: ~22 MiB
  - `occupify-node-exporter`: ~14 MiB
  - **Total Container Memory**: **~234 MiB** (comfortably within the 952 MiB RAM limit).
- **Swap Protection**: 3GB active swap space (`/swapfile`) persisted in `/etc/fstab`.
- **Disk Protection**: 7-day retention on Loki and Tempo; 1.5GB cap on Prometheus TSDB; Docker log rotation (`10m`, 3 files).
- **Nginx Ingress**: Clean HTTP reverse proxy without WebSocket overhead, providing rock-solid connection stability.

---

## 6. Repository & Operations Runbook

The complete codebase is stored in `occupify-obs` (`https://github.com/Occupify/occupify-obs.git`):

```bash
# View stack status on Web EC2
ssh aws_bastion "ssh web 'cd /opt/occupify-obs && sudo docker compose ps'"

# Run full 19-point automated verification suite
cd ../occupify-obs && make verify
```
