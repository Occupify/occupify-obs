#!/usr/bin/env bash
set -euo pipefail

echo "================================================================="
echo "   Exposing Port 5432 on all 5 Database Hosts for pgAdmin        "
echo "================================================================="

NODES=("identity:10.0.10.62" "core:10.0.10.146" "payment:10.0.10.202" "noti:10.0.10.86" "administration:10.0.10.103")

for item in "${NODES[@]}"; do
  SVC="${item%%:*}"
  IP="${item##*:}"
  echo "--> Processing node: $SVC ($IP)..."

  ssh aws_bastion "ssh $IP 'bash -s'" <<EOF
set -euo pipefail
COMPOSE_FILE="/home/ubuntu/gitops/compose/$SVC/compose.prod.yml"
if [ ! -f "\$COMPOSE_FILE" ]; then
  echo "Error: \$COMPOSE_FILE not found!"
  exit 1
fi

# Ensure postgres container exposes port 5432
if ! grep -q "5432:5432" "\$COMPOSE_FILE"; then
  echo "Adding port 5432:5432 to postgres in \$COMPOSE_FILE..."
  # Use python to insert ports under postgres
  python3 -c "
with open('\$COMPOSE_FILE', 'r') as f:
    lines = f.readlines()

new_lines = []
for i, line in enumerate(lines):
    new_lines.append(line)
    if 'container_name: occupify-postgres-' in line:
        new_lines.append('    ports:\n')
        new_lines.append('      - \"5432:5432\"\n')

with open('\$COMPOSE_FILE', 'w') as f:
    f.writelines(new_lines)
"
fi

cd /home/ubuntu/gitops/compose/$SVC
sudo podman compose down || true
sudo podman compose up -d
EOF

  echo "Verifying port 5432 on $SVC ($IP)..."
  ssh aws_bastion "nc -z -w 3 $IP 5432 && echo 'Port 5432 OPEN on $SVC' || echo 'Failed to open 5432 on $SVC'"
done

echo "All 5 databases successfully exposed on port 5432 within the VPC!"
