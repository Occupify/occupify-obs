#!/usr/bin/env bash
set -euo pipefail

echo "================================================================="
echo "   Enabling OpenTelemetry Distributed Tracing on Microservices   "
echo "================================================================="

OTEL_AGENT_URL="https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/latest/download/opentelemetry-javaagent.jar"
NODES=("gateway:10.0.10.143" "identity:10.0.10.62" "core:10.0.10.146" "payment:10.0.10.202" "noti:10.0.10.86" "administration:10.0.10.103")

for item in "${NODES[@]}"; do
  SVC="${item%%:*}"
  IP="${item##*:}"
  echo "--> Provisioning OpenTelemetry Java Agent on $SVC ($IP)..."

  ssh aws_bastion "ssh $IP 'bash -s'" <<EOF
set -euo pipefail
sudo mkdir -p /opt/otel
if [ ! -f /opt/otel/opentelemetry-javaagent.jar ]; then
  echo "Downloading OpenTelemetry Java Agent..."
  sudo curl -sSL "$OTEL_AGENT_URL" -o /opt/otel/opentelemetry-javaagent.jar
  sudo chmod 644 /opt/otel/opentelemetry-javaagent.jar
fi

echo "OpenTelemetry Java Agent ready on $SVC!"
EOF
done

echo "OpenTelemetry distributed tracing agent ready across all services!"
