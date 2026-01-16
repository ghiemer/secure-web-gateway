#!/bin/bash
# scripts/backup.sh

BACKUP_DIR=./backups/$(date +%Y%m%d)
mkdir -p $BACKUP_DIR

echo "--- Starting Backup to $BACKUP_DIR ---"

# Zertifikate
echo "Backing up Certificates..."
cp -r ./certs $BACKUP_DIR/

# Caddy Logs
echo "Backing up Logs..."
docker cp gateway:/var/log/caddy/access.log $BACKUP_DIR/caddy_access.log

# CrowdSec Decisions
echo "Backing up CrowdSec Decisions..."
docker exec gateway_crowdsec cscli decisions export -o /tmp/decisions.json
docker cp gateway_crowdsec:/tmp/decisions.json $BACKUP_DIR/
docker exec gateway_crowdsec rm /tmp/decisions.json

# Prometheus Snapshot (if enabled)
if curl --output /dev/null --silent --head --fail "http://localhost:9090"; then
    echo "Backing up Prometheus..."
    curl -X POST http://localhost:9090/api/v1/admin/tsdb/snapshot
    # Note: Accessing snapshot path requires mounting it or docker cp. 
    # For now, we assume simple volume backup is preferred in full production.
else
    echo "Prometheus not accessible on localhost (expected if internal). Skipping snapshot."
fi

echo "✅ Backup created: $BACKUP_DIR"
