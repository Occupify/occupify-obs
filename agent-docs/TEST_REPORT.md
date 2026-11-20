# Occupify Observability & Multi-Database Administration Test Report

## 1. Executive Summary & Quality Gate Status

- **Verification Date**: November 20, 2026
- **Result**: **19 PASSED, 0 FAILED (100% Pass Rate)**
- **Quality Gate**: **PASSED (All Tiers Satisfied)**
- **Target Repository**: `occupify-obs` (`https://github.com/Occupify/occupify-obs.git`)

---

## 2. Dev-to-Prod Test Failure Taxonomy Results

### Tier 1: Dev / Unit & Logic Verification
| Test ID | Test Case | Target / Command | Result |
|---|---|---|---|
| **T1-01** | Compose Syntax & Schema | `docker compose config` on Web EC2 | **PASS** |
| **T1-02** | Loki YAML Grammar | Schema v13, TSDB filesystem storage | **PASS** |
| **T1-03** | Tempo YAML Grammar | OTLP gRPC (:4317) & HTTP (:4318) endpoints | **PASS** |
| **T1-04** | Port Collision Audit | `ss -tulpn` on ports 3000, 3100, 3200, 5050, 9090, 9100 | **PASS** |

### Tier 2: CI / Integration & Contract Verification
| Test ID | Test Case | Target / Endpoint | Result |
|---|---|---|---|
| **T2-01** | Grafana Core Service Health | `http://127.0.0.1:3000/api/health` returns `ok` | **PASS** |
| **T2-02** | Prometheus Engine Health | `http://127.0.0.1:9090/-/healthy` returns healthy | **PASS** |
| **T2-03** | Loki Aggregator Ready | `http://127.0.0.1:3100/ready` returns ready | **PASS** |
| **T2-04** | Tempo Tracing Status | `http://127.0.0.1:3200/status` returns tempo | **PASS** |
| **T2-05** | pgAdmin Internal Daemon | `http://127.0.0.1:5050/` returns HTTP 302 | **PASS** |
| **T2-06** | Prometheus Scrape Targets | All 7 Node Exporters (`10.0.1.78`, `10.0.10.x:9100`) report `health: up` | **PASS** |
| **T2-07** | OTLP Trace Span Ingestion | Synthetic OTLP HTTP trace span to `:4318` accepted (HTTP 200) | **PASS** |
| **T2-08** | Tempo Trace Retrieval | Query `GET /api/traces/<traceId>` returns valid span tree | **PASS** |
| **T2-09** | Multi-Service Log Ingestion | Loki streams active for all 6 microservices (`gateway`, `identity`, `core`, `payment`, `noti`, `admin`) | **PASS** |

### Tier 3: Staging / Parity & Ingress Verification
| Test ID | Test Case | Target / Verification | Result |
|---|---|---|---|
| **T3-01** | Grafana Ingress HTTPS | `https://occupify.tienvm.dpdns.org/grafana/` returns HTTP 302 -> `/grafana/login` | **PASS** |
| **T3-02** | pgAdmin Ingress HTTPS | `https://occupify.tienvm.dpdns.org/pgadmin/` returns HTTP 302 -> `/pgadmin/login` | **PASS** |
| **T3-03** | Let's Encrypt TLS Certificate | Handshake valid on port 443 with domain subject match | **PASS** |
| **T3-04** | Pre-Provisioned Datasources | Prometheus (default), Loki, and Tempo configured and accessible | **PASS** |
| **T3-05** | Pre-Provisioned Dashboards | Cluster Infrastructure Overview & Unified Log Explorer loaded | **PASS** |
| **T3-06** | Identity DB Connection | Port 5432 open on `10.0.10.62`, 10 public tables queried | **PASS** |
| **T3-07** | Core DB Connection | Port 5432 open on `10.0.10.146`, 16 public tables queried | **PASS** |
| **T3-08** | Payment DB Connection | Port 5432 open on `10.0.10.202`, 5 public tables queried | **PASS** |
| **T3-09** | Notification DB Connection | Port 5432 open on `10.0.10.86`, 3 public tables queried | **PASS** |
| **T3-10** | Administration DB Connection | Port 5432 open on `10.0.10.103`, 9 public tables queried | **PASS** |

### Tier 4: Production Reality & Worst-Case Verification
| Test ID | Test Case | Target / Verification | Result |
|---|---|---|---|
| **T4-01** | Memory Cap Enforcement | Total stack consumes ~234MB RAM out of 952MB physical memory | **PASS** |
| **T4-02** | Swap Shield Protection | 3GB swap file (`/swapfile`) actively shielding host stability | **PASS** |
| **T4-03** | Log Noise Filtering | Repetitive `/actuator/health` 200 logs dropped at Promtail edge | **PASS** |
| **T4-04** | Container Reboot Safety | `restart: unless-stopped` configured across all services | **PASS** |

---

## 3. Real-World Persona Verification

1. **DevOps / SRE Persona**:
   - Accesses `https://occupify.tienvm.dpdns.org/grafana/` with `admin` / `occ123!@#`.
   - Opens "Occupify Cluster Infrastructure Overview": Real-time CPU, RAM, Disk, and Network graphs populate from all 7 nodes.
   - Opens "Occupify Unified Log Explorer": Filters logs by service (`core`, `gateway`), searches for `Corr-*` IDs.
2. **Database Administrator (DBA) Persona**:
   - Accesses `https://occupify.tienvm.dpdns.org/pgadmin/` with `admin@occupify.vn` / `occ123!@#`.
   - Views the 5 pre-configured databases in the server tree: Identity, Core, Payment, Notification, and Administration.
   - Executes SQL queries against any database with instant sub-millisecond query execution.
