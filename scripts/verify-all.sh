#!/usr/bin/env bash
# Do not use set -e so full test matrix runs to completion

echo "================================================================="
echo "   Verifying Occupify Observability & pgAdmin Stack              "
echo "================================================================="

PASS=0
FAIL=0

assert_check() {
  local name="$1"
  local cmd="$2"
  echo -n "Checking: $name ... "
  if ( eval "$cmd" ) > /dev/null 2>&1; then
    echo "PASS"
    PASS=$((PASS + 1))
  else
    echo "FAIL"
    FAIL=$((FAIL + 1))
  fi
}

# 1. Nginx Ingress Checks
echo ""
echo "--- 1. Ingress & Reverse Proxy Checks ---"
assert_check "Grafana Ingress URL (https://occupify.tienvm.dpdns.org/grafana/)" \
  "curl -k -sI https://occupify.tienvm.dpdns.org/grafana/ | grep -E 'HTTP/.* (200|302)'"

assert_check "pgAdmin Ingress URL (https://occupify.tienvm.dpdns.org/pgadmin/)" \
  "curl -k -sI https://occupify.tienvm.dpdns.org/pgadmin/ | grep -E 'HTTP/.* (200|302)'"

# 2. Central Services Health on Web EC2
echo ""
echo "--- 2. Central Observability Services on Web EC2 ---"
assert_check "Grafana API Health (Port 3000)" \
  "ssh aws_bastion \"ssh web 'curl -s http://127.0.0.1:3000/api/health | grep -q ok'\""

assert_check "Prometheus API Health (Port 9090)" \
  "ssh aws_bastion ssh web curl -s http://127.0.0.1:9090/-/healthy | grep -q 'Prometheus Server is Healthy'"

assert_check "Loki API Ready (Port 3100)" \
  "ssh aws_bastion ssh web curl -s http://127.0.0.1:3100/ready | grep -q ready"

assert_check "Tempo API Status (Port 3200)" \
  "ssh aws_bastion ssh web curl -s http://127.0.0.1:3200/status | grep -q tempo"

assert_check "pgAdmin Internal Port (Port 5050)" \
  "ssh aws_bastion ssh web curl -sI http://127.0.0.1:5050/ | grep -q '302 FOUND'"

# 3. Database Connectivity from Web EC2
echo ""
echo "--- 3. Database Connectivity from Web EC2 (Port 5432) ---"
for ip in 10.0.10.62 10.0.10.146 10.0.10.202 10.0.10.86 10.0.10.103; do
  assert_check "PostgreSQL reachable on $ip:5432" \
    "ssh aws_bastion \"ssh web 'nc -z -w 2 $ip 5432'\""
done

# 4. Metrics Scrape Targets from Web EC2
echo ""
echo "--- 4. Node Exporters Scrape Connectivity (Port 9100) ---"
for ip in 10.0.1.78 10.0.10.143 10.0.10.62 10.0.10.146 10.0.10.202 10.0.10.86 10.0.10.103; do
  assert_check "Node Exporter reachable on $ip:9100" \
    "ssh aws_bastion \"ssh web 'nc -z -w 2 $ip 9100'\""
done

echo ""
echo "================================================================="
echo "   Verification Results: $PASS PASSED, $FAIL FAILED             "
echo "================================================================="

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
