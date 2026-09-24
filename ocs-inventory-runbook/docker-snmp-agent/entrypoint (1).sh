#!/bin/bash
set -e

OCS_SERVER="${OCS_SERVER:-https://localhost/ocsinventory}"
TAG="${OCS_TAG:-SNMP-COLLECTOR}"
INTERVAL="${OCS_INTERVAL:-3600}"

echo "[entrypoint] SNMP-collector agent starting. Server=$OCS_SERVER Tag=$TAG"

while true; do
    echo "[entrypoint] $(date) running ocsinventory-agent..."
    ocsinventory-agent \
        --server="$OCS_SERVER" \
        --tag="$TAG" \
        --ssl=0 \
        --debug || echo "[entrypoint] agent run failed, will retry next cycle"
    sleep "$INTERVAL"
done
