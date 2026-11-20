#!/usr/bin/env bash
set -euo pipefail

echo "================================================================="
echo "   Deploying Central Observability & pgAdmin Stack to Web EC2    "
echo "================================================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "--> 1. Syncing occupify-obs repository to Web EC2 (/opt/occupify-obs)..."
ssh aws_bastion "ssh web 'sudo mkdir -p /opt/occupify-obs && sudo chown -R ubuntu:ubuntu /opt/occupify-obs'"

# Create tarball locally and stream to Web EC2
tar -czf - -C "$REPO_DIR" \
  --exclude=".git" \
  docker-compose.yml config grafana nginx | \
  ssh aws_bastion "ssh web 'tar -xzf - -C /opt/occupify-obs'"

echo "--> 2. Configuring Nginx Reverse Proxy on Web EC2..."
ssh aws_bastion "ssh web 'bash -s'" << 'EOF'
set -euo pipefail
NGINX_CONF="/etc/nginx/conf.d/occupify-web.conf"

if ! grep -q "location /grafana/" "$NGINX_CONF"; then
  echo "Injecting /grafana/ and /pgadmin/ proxy locations into Nginx config..."
  sudo sed -i '/# Internal API reverse proxy to AWS Gateway EC2/i \
    # Grafana reverse proxy\
    location /grafana/ {\
        proxy_pass http://127.0.0.1:3000;\
        proxy_set_header Host $http_host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto $scheme;\
        proxy_connect_timeout 10s;\
        proxy_read_timeout 60s;\
    }\
\
    # pgAdmin 4 reverse proxy\
    location /pgadmin/ {\
        proxy_pass http://127.0.0.1:5050/;\
        proxy_set_header X-Script-Name /pgadmin;\
        proxy_set_header Host $http_host;\
        proxy_set_header X-Real-IP $remote_addr;\
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;\
        proxy_set_header X-Forwarded-Proto $scheme;\
        proxy_redirect off;\
        proxy_connect_timeout 10s;\
        proxy_read_timeout 120s;\
    }\
' "$NGINX_CONF"
fi

sudo nginx -t
sudo systemctl reload nginx
echo "Nginx successfully reloaded!"
EOF

echo "--> 3. Launching Central Observability & pgAdmin Stack on Web EC2..."
ssh aws_bastion "ssh web 'bash -s'" << 'EOF'
set -euo pipefail
cd /opt/occupify-obs
sudo docker compose down --remove-orphans || true
sudo docker compose up -d
sleep 5
sudo docker compose ps
EOF

echo "Central Stack deployment complete on Web EC2!"
