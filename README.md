# Occupify Observability & Multi-Database Administration Stack

Unified, production-grade observability and database administration platform for Occupify:
- **Central Stack**: Grafana (UI), Prometheus (Metrics), Grafana Loki (Logs), Grafana Tempo (Distributed Tracing), pgAdmin 4 (Multi-Database Admin), and Node Exporter.
- **Node Forwarders**: Promtail (Container log forwarding) and Node Exporter (Compute/Memory/Disk/Network metrics) running across all 6 service nodes.

---

## 1. Access Endpoints & Credentials

| Service | Access URL | Credentials |
|---|---|---|
| **Grafana Observability** | `https://occupify.tienvm.dpdns.org/grafana/` | Username: `admin`<br>Password: `occ123!@#` |
| **pgAdmin 4 Administration** | `https://occupify.tienvm.dpdns.org/pgadmin/` | Email: `admin@occupify.vn`<br>Password: `occ123!@#` |

---

## 2. Pre-Connected Databases in pgAdmin 4

| Database Name | Host IP | Port | Database | Username |
|---|---|---|---|---|
| **Occupify Identity DB** | `10.0.10.62` | `5432` | `occupify_identity` | `postgres` |
| **Occupify Core DB** | `10.0.10.146` | `5432` | `occupify_core` | `postgres` |
| **Occupify Payment DB** | `10.0.10.202` | `5432` | `occupify_payment` | `postgres` |
| **Occupify Notification DB** | `10.0.10.86` | `5432` | `occupify_noti` | `postgres` |
| **Occupify Administration DB** | `10.0.10.103` | `5432` | `occupify_administration` | `postgres` |

---

## 3. Network Architecture & Ingress Routing

- **Nginx Ingress on Web EC2 (`10.0.1.78`)**:
  - `/grafana/` $\to$ `http://127.0.0.1:3000/` (Grafana UI, HTTP polling mode)
  - `/pgadmin/` $\to$ `http://127.0.0.1:5050/` (pgAdmin 4 UI with `X-Script-Name: /pgadmin`)
- **Telemetry Ingestion Ports (Private VPC `10.0.0.0/16`)**:
  - `10.0.1.78:3100`: Loki Log Push endpoint (`/loki/api/v1/push`)
  - `10.0.1.78:4318`: Tempo OTLP HTTP trace span receiver (`/v1/traces`)
  - `10.0.1.78:4317`: Tempo OTLP gRPC trace span receiver
  - `10.0.1.78:9090`: Prometheus Server metrics endpoint
- **Host Metrics Scrape**:
  - Prometheus on Web scrapes port `9100` on all 7 EC2 instances (`web`, `gateway`, `identity`, `core`, `payment`, `noti`, `admin`).

---

## 4. Operational Scripts

```bash
# Deploy or update central stack on Web EC2
make deploy-web

# Expose port 5432 on all 5 database nodes
make expose-db

# Deploy Node Exporter and Promtail to all 6 service nodes
make deploy-agents

# Run full end-to-end verification
make verify
```
