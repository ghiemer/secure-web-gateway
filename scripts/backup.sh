#!/bin/bash
# scripts/backup.sh
# Secure Backup Script with Optional Encryption (SEC-008)

set -e

# Configuration
BACKUP_BASE_DIR=./backups
BACKUP_DIR=$BACKUP_BASE_DIR/$(date +%Y%m%d_%H%M%S)
ENCRYPT=${ENCRYPT:-false}
BACKUP_PASSWORD=${BACKUP_PASSWORD:-}
RETENTION_DAYS=${RETENTION_DAYS:-30}

mkdir -p $BACKUP_DIR
chmod 700 $BACKUP_BASE_DIR

echo "╔══════════════════════════════════════════════════════════════╗"
echo "║               Secure Gateway Backup                          ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📁 Backup Directory: $BACKUP_DIR"
echo "🔐 Encryption: $ENCRYPT"
echo ""

# Function to encrypt file if enabled
encrypt_file() {
    local file=$1
    if [ "$ENCRYPT" = "true" ] && [ -n "$BACKUP_PASSWORD" ]; then
        echo "   🔐 Encrypting $(basename $file)..."
        openssl enc -aes-256-cbc -salt -pbkdf2 -in "$file" -out "$file.enc" -pass pass:"$BACKUP_PASSWORD"
        rm "$file"
        echo "   ✅ Encrypted: $(basename $file).enc"
    fi
}

# Certificates (excluding private keys from unencrypted backup)
echo "📜 Backing up Certificates..."
if [ "$ENCRYPT" = "true" ]; then
    cp -r ./certs $BACKUP_DIR/
    tar -czf $BACKUP_DIR/certs.tar.gz -C $BACKUP_DIR certs
    rm -rf $BACKUP_DIR/certs
    encrypt_file $BACKUP_DIR/certs.tar.gz
else
    # Only backup public certs if not encrypting
    mkdir -p $BACKUP_DIR/certs
    cp ./certs/*.crt $BACKUP_DIR/certs/ 2>/dev/null || true
    echo "   ⚠️  Private keys NOT backed up (enable encryption with ENCRYPT=true)"
fi

# Caddy Logs
echo "📋 Backing up Logs..."
docker cp gateway:/var/log/caddy/access.log $BACKUP_DIR/caddy_access.log 2>/dev/null || echo "   ⚠️  Caddy logs not available"
encrypt_file $BACKUP_DIR/caddy_access.log 2>/dev/null || true

# CrowdSec Decisions
echo "🛡️  Backing up CrowdSec Decisions..."
if docker exec gateway_crowdsec cscli decisions export -o /tmp/decisions.json 2>/dev/null; then
    docker cp gateway_crowdsec:/tmp/decisions.json $BACKUP_DIR/
    docker exec gateway_crowdsec rm /tmp/decisions.json
    encrypt_file $BACKUP_DIR/decisions.json
else
    echo "   ⚠️  CrowdSec decisions not available"
fi

# Configuration backup
echo "⚙️  Backing up Configuration..."
cp ./services.conf $BACKUP_DIR/ 2>/dev/null || true
cp ./gateway/Caddyfile $BACKUP_DIR/ 2>/dev/null || true

# Cleanup old backups
echo ""
echo "🧹 Cleaning up backups older than $RETENTION_DAYS days..."
find $BACKUP_BASE_DIR -maxdepth 1 -type d -mtime +$RETENTION_DAYS -exec rm -rf {} \; 2>/dev/null || true

# Set restrictive permissions
chmod -R 600 $BACKUP_DIR/*
chmod 700 $BACKUP_DIR

echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║ ✅ Backup Complete                                           ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📁 Location: $BACKUP_DIR"
ls -la $BACKUP_DIR
echo ""
echo "💡 To restore encrypted files:"
echo "   openssl enc -aes-256-cbc -d -pbkdf2 -in file.enc -out file -pass pass:YOUR_PASSWORD"
echo ""
