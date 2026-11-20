#!/usr/bin/env bash
set -euo pipefail

echo "================================================================="
echo "   Deploying Node Exporter & Promtail to all 6 Service Nodes     "
echo "================================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

NODES=("gateway:10.0.10.143" "identity:10.0.10.62" "core:10.0.10.146" "payment:10.0.10.202" "noti:10.0.10.86" "administration:10.0.10.103")

for item in "${NODES[@]}"; do
  SVC="${item%%:*}"
  IP="${item##*:}"
  echo "--> Deploying telemetry forwarder on: $SVC ($IP)..."

  # Customize promtail.yaml for the specific node
  SED_CMD="s/__SERVICE_NAME__/$SVC/g; s/__HOST_IP__/$IP/g"
  PROMTAIL_CONF=$(sed "$SED_CMD" "$REPO_DIR/agent/promtail.yaml")

  ssh aws_bastion "ssh $IP 'bash -s'" <<EOF
set -euo pipefail
sudo mkdir -p /opt/occupify-agent
sudo chown -R ubuntu:ubuntu /opt/occupify-agent

cat << 'INNER_EOF' > /opt/occupify-agent/compose.agent.yml
$(cat "$REPO_DIR/agent/compose.agent.yml")
INNER_EOF

cat << 'INNER_EOF' > /opt/occupify-agent/promtail.yaml
$PROMTAIL_CONF
INNER_EOF

cd /opt/occupify-agent
sudo podman compose down || true
sudo podman compose up -d
EOF

  echo "Verifying Node Exporter on $SVC ($IP:9100)..."
  ssh aws_bastion "nc -z -w 3 $IP 9100 && echo 'Node Exporter UP on $SVC' || echo 'Node Exporter NOT reachable on $SVC'"
done

echo "Telemetry forwarders successfully launched across all 6 service nodes!"
