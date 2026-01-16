# 🤖 AI Agent Deployment Guide

This document provides comprehensive instructions for AI agents (GitHub Copilot, Claude, GPT, etc.) to autonomously deploy and configure the Secure Web Gateway.

---

## 📋 Pre-Deployment Checklist

Before starting deployment, verify these requirements:

### System Requirements
- [ ] Docker Engine 24.0+ installed
- [ ] Docker Compose v2.20+ installed
- [ ] GNU Make installed
- [ ] OpenSSL 3.0+ installed
- [ ] Git installed
- [ ] Minimum 2GB RAM available
- [ ] Minimum 10GB disk space

### Network Requirements
- [ ] Ports 80 and 443 available
- [ ] DNS records configured for domains
- [ ] Outbound internet access for Let's Encrypt

### Verification Commands
```bash
# Verify all requirements
docker --version          # Expected: Docker version 24.x+
docker compose version    # Expected: Docker Compose version v2.20+
make --version           # Expected: GNU Make 4.x+
openssl version          # Expected: OpenSSL 3.x+
```

---

## 🔧 Configuration Reference

### File: `.env`

The environment configuration file. Copy from `.env.example` and customize.

| Variable | Required | Default | Description | Example |
|----------|----------|---------|-------------|---------|
| `GATEWAY_EMAIL` | ✅ Yes | `admin@example.com` | Email for Let's Encrypt certificates | `admin@company.com` |
| `COMPOSE_PROJECT_NAME` | ❌ No | `hardened_gateway` | Docker Compose project name | `prod_gateway` |
| `MONITORING_DOMAIN` | ❌ No | `monitor.example.com` | Domain for Grafana access | `grafana.company.com` |
| `MONITORING_ALLOWED_IPS` | ❌ No | *(empty)* | IP whitelist for monitoring | `10.0.0.0/8,192.168.1.0/24` |
| `CROWDSEC_BOUNCER_API_KEY` | ✅ Yes | *(empty)* | CrowdSec API key (generated) | `abc123...` |
| `GRAFANA_PASSWORD` | ✅ Yes | `admin` | Grafana admin password (auto-generated) | `Kj8#mP2$xQ...` |

#### Example `.env` for Production
```bash
# Production Configuration
GATEWAY_EMAIL=devops@company.com
COMPOSE_PROJECT_NAME=production_gateway
MONITORING_DOMAIN=monitor.company.com
MONITORING_ALLOWED_IPS=10.0.0.0/8,192.168.0.0/16,203.0.113.50

# Secrets (populated during setup)
CROWDSEC_BOUNCER_API_KEY=your-api-key-here
GRAFANA_PASSWORD=auto-generated-secure-password
```

---

### File: `services.conf`

Defines backend services to proxy. **Space-separated** format.

| Column | Description | Constraints |
|--------|-------------|-------------|
| `ServiceName` | Unique identifier | Alphanumeric, hyphens allowed |
| `PublicDomain` | Public FQDN | Valid domain, DNS must resolve |
| `InternalHost` | Docker container name | Must match container_name in docker-compose |
| `InternalPort` | Backend HTTPS port | Numeric, typically 443 or 8443 |

#### Format
```
# ServiceName    PublicDomain              InternalHost         InternalPort
```

#### Example `services.conf`
```bash
# ============================================================================
# Production Services
# ============================================================================

# Main web application
webapp           app.company.com           webapp_caddy         443

# REST API service
api              api.company.com           api_caddy            443

# Admin dashboard
admin            admin.company.com         admin_caddy          443

# Development staging
staging          staging.company.com       staging_caddy        443
```

#### Rules
1. One service per line
2. Lines starting with `#` are comments
3. Empty lines are ignored
4. Use tabs or spaces as separators
5. Domain must be unique across all services

---

### File: `docker-compose.override.yml`

Server-specific customizations. Auto-created on first `make run`.

#### Example: Resource Limits
```yaml
services:
  gateway:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 1G
        reservations:
          cpus: '0.5'
          memory: 256M

  grafana:
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
```

#### Example: Debug Mode (Expose Ports)
```yaml
services:
  grafana:
    ports:
      - "3000:3000"  # Direct Grafana access
  
  prometheus:
    ports:
      - "9090:9090"  # Direct Prometheus access
```

#### Example: Custom Logging
```yaml
services:
  gateway:
    logging:
      driver: "json-file"
      options:
        max-size: "50m"
        max-file: "10"
```

#### Example: Add Custom Service
```yaml
services:
  myapp:
    image: mycompany/myapp:latest
    container_name: myapp_caddy
    restart: unless-stopped
    networks:
      - gateway_net
    volumes:
      - ./certs/myapp_caddy.crt:/etc/ssl/certs/server.crt:ro
      - ./certs/myapp_caddy.key:/etc/ssl/private/server.key:ro
      - ./certs/ca.crt:/etc/ssl/certs/ca.crt:ro
    security_opt:
      - no-new-privileges:true
```

---

## 🚀 Deployment Steps (AI Agent Instructions)

### Step 1: Clone and Navigate

```bash
git clone <repository-url> secure-web-gateway
cd secure-web-gateway
```

### Step 2: Create Environment Configuration

```bash
# Copy example configuration
cp .env.example .env

# Edit .env with actual values
# Required: GATEWAY_EMAIL must be valid for Let's Encrypt
```

**AI Agent Action:** Replace placeholder values in `.env`:
```bash
sed -i 's/admin@example.com/actual-email@company.com/' .env
sed -i 's/monitor.example.com/actual-monitor-domain.com/' .env
```

### Step 3: Configure Services

```bash
# Clear example entries and add real services
cat > services.conf << 'EOF'
# ============================================================================
# Services Configuration
# ============================================================================
# Format: ServiceName    PublicDomain          InternalHost       InternalPort

myapp            app.company.com         myapp_caddy          443
EOF
```

### Step 4: Initial CrowdSec Setup

```bash
# Start CrowdSec first (required for API key generation)
docker compose up -d crowdsec

# Wait for CrowdSec to initialize (check logs)
sleep 10
docker compose logs crowdsec | tail -5

# Generate bouncer API key
CROWDSEC_KEY=$(docker exec gateway_crowdsec cscli bouncers add gateway-bouncer -o raw)
echo "Generated CrowdSec API Key: $CROWDSEC_KEY"

# Add key to .env
sed -i "s/CROWDSEC_BOUNCER_API_KEY=.*/CROWDSEC_BOUNCER_API_KEY=$CROWDSEC_KEY/" .env
```

### Step 5: Run Full Deployment

```bash
make run
```

**What `make run` executes:**
1. `generate-secrets` - Creates `.env` if missing, generates Grafana password
2. `preflight` - Validates configuration
3. `certs` - Generates CA and service certificates
4. `caddyfile` - Creates hardened Caddyfile
5. `docker compose up -d` - Starts all services

### Step 6: Verify Deployment

```bash
# Check all containers are running
docker compose ps

# Expected output:
# NAME                STATUS              PORTS
# gateway             Up (healthy)        0.0.0.0:80->80/tcp, 0.0.0.0:443->443/tcp
# gateway_crowdsec    Up (healthy)        
# gateway_grafana     Up (healthy)        
# gateway_prometheus  Up (healthy)        

# Check gateway logs
docker compose logs gateway --tail 20

# Verify HTTPS is working
curl -I https://your-domain.com
```

---

## 🔄 Adding New Services (AI Agent Workflow)

### Scenario: Add new service `blog.company.com`

```bash
# Step 1: Add to services.conf
echo "blog             blog.company.com        blog_caddy           443" >> services.conf

# Step 2: Regenerate certificates and Caddyfile
make run

# Step 3: Verify new certificate was created
ls -la certs/blog_caddy.*

# Step 4: Update backend service docker-compose to use certificates
# (See project-template/README.md for full example)
```

---

## 🔐 Certificate Management

### Certificate Structure
```
certs/
├── ca.crt              # Root CA certificate (public)
├── ca.key              # Root CA private key (SENSITIVE)
├── ca.srl              # CA serial number
├── gateway-client.crt  # Gateway client certificate
├── gateway-client.key  # Gateway client key
├── gateway-client.csr  # Gateway CSR (can be deleted)
├── <service>.crt       # Service certificate
└── <service>.key       # Service private key
```

### Check Certificate Expiry
```bash
./scripts/check-certs.sh

# Expected output:
# ┌──────────────────────────────────────────────────────────────┐
# │ Certificate               │ Expires      │ Status           │
# ├──────────────────────────────────────────────────────────────┤
# │ ca.crt                    │ 2031-01-16   │ ✅ 1825d left    │
# │ gateway-client.crt        │ 2027-01-16   │ ✅ 365d left     │
# │ myapp_caddy.crt           │ 2027-01-16   │ ✅ 365d left     │
# └──────────────────────────────────────────────────────────────┘
```

### Renew Certificates
```bash
# Delete expired certificates
rm certs/myapp_caddy.*

# Regenerate
make certs

# Restart services to use new certificates
docker compose restart
```

---

## 📊 Monitoring Setup

### Access Grafana
1. URL: `https://<MONITORING_DOMAIN>`
2. Username: `admin`
3. Password: Check `.env` file (`GRAFANA_PASSWORD`)

### Import Caddy Dashboard
1. Go to Dashboards → Import
2. Enter Dashboard ID: `13460`
3. Select Prometheus data source
4. Click Import

### Prometheus Targets
Verify scrape targets at: Grafana → Explore → Prometheus → Status → Targets

Expected targets:
- `gateway:2019` - Caddy metrics

---

## 🛠️ Troubleshooting

### Problem: Container won't start

```bash
# Check logs
docker compose logs <service-name>

# Check health status
docker inspect <container-name> --format='{{.State.Health.Status}}'
```

### Problem: CrowdSec bouncer not working

```bash
# Verify API key is set
grep CROWDSEC_BOUNCER_API_KEY .env

# Test CrowdSec connection
docker exec gateway_crowdsec cscli bouncers list

# Check bouncer logs
docker compose logs gateway | grep -i crowdsec
```

### Problem: Certificate errors

```bash
# Verify certificate chain
openssl verify -CAfile certs/ca.crt certs/myapp_caddy.crt

# Check certificate details
openssl x509 -in certs/myapp_caddy.crt -text -noout

# Regenerate specific certificate
rm certs/myapp_caddy.*
make certs
```

### Problem: Let's Encrypt rate limits

```bash
# Check Caddy logs for rate limit errors
docker compose logs gateway | grep -i "rate limit"

# Use staging environment for testing (add to Caddyfile globals):
# acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
```

---

## 🔄 Complete Redeployment

If you need to start fresh:

```bash
# Stop and remove everything
docker compose down -v

# Clean generated files
make clean
rm -rf certs/ gateway/Caddyfile docker-compose.override.yml

# Remove .env to regenerate
rm .env

# Start fresh
make run

# Regenerate CrowdSec API key (required after volume removal)
docker exec gateway_crowdsec cscli bouncers add gateway-bouncer
# Add new key to .env and restart
docker compose restart gateway
```

---

## 📝 AI Agent Deployment Script

Complete automated deployment script for AI agents:

```bash
#!/bin/bash
# AI Agent Deployment Script for Secure Web Gateway
set -e

# Configuration (AI Agent should replace these)
EMAIL="admin@company.com"
MONITORING_DOMAIN="monitor.company.com"
MONITORING_IPS="10.0.0.0/8"
SERVICES=(
    "webapp app.company.com webapp_caddy 443"
    "api api.company.com api_caddy 443"
)

echo "🚀 Starting Secure Web Gateway Deployment..."

# Step 1: Environment Setup
cp .env.example .env
sed -i "s|GATEWAY_EMAIL=.*|GATEWAY_EMAIL=$EMAIL|" .env
sed -i "s|MONITORING_DOMAIN=.*|MONITORING_DOMAIN=$MONITORING_DOMAIN|" .env
sed -i "s|MONITORING_ALLOWED_IPS=.*|MONITORING_ALLOWED_IPS=$MONITORING_IPS|" .env

# Step 2: Services Configuration
cat > services.conf << 'HEADER'
# ============================================================================
# Services Configuration (Auto-generated by AI Agent)
# ============================================================================
HEADER

for service in "${SERVICES[@]}"; do
    echo "$service" >> services.conf
done

# Step 3: CrowdSec Setup
docker compose up -d crowdsec
echo "⏳ Waiting for CrowdSec to initialize..."
sleep 15

CROWDSEC_KEY=$(docker exec gateway_crowdsec cscli bouncers add gateway-bouncer -o raw 2>/dev/null || echo "")
if [ -z "$CROWDSEC_KEY" ]; then
    echo "⚠️  CrowdSec key may already exist, checking..."
    docker exec gateway_crowdsec cscli bouncers list
else
    sed -i "s|CROWDSEC_BOUNCER_API_KEY=.*|CROWDSEC_BOUNCER_API_KEY=$CROWDSEC_KEY|" .env
    echo "✅ CrowdSec API key configured"
fi

# Step 4: Full Deployment
make run

# Step 5: Verification
echo "🔍 Verifying deployment..."
sleep 10
docker compose ps

# Step 6: Display Summary
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           ✅ Deployment Complete                             ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "📊 Grafana:  https://$MONITORING_DOMAIN"
echo "🔐 Password: $(grep GRAFANA_PASSWORD .env | cut -d= -f2)"
echo ""
echo "🔍 Check certificate status: ./scripts/check-certs.sh"
echo "📦 Create backup: ENCRYPT=true ./scripts/backup.sh"
```

---

## ✅ Post-Deployment Verification Checklist

AI Agent should verify these after deployment:

- [ ] All containers show "healthy" status
- [ ] HTTPS responds on all configured domains
- [ ] Let's Encrypt certificates are valid (not staging)
- [ ] Grafana is accessible via monitoring domain
- [ ] Prometheus is scraping metrics
- [ ] CrowdSec is processing logs
- [ ] Rate limiting is active (test with: `ab -n 100 -c 10 https://domain/`)
- [ ] Security headers are present (check with: `curl -I https://domain/`)

```bash
# Quick verification script
echo "Checking container health..."
docker compose ps --format "{{.Name}}: {{.Status}}" | grep -v healthy && echo "⚠️  Some containers unhealthy" || echo "✅ All containers healthy"

echo "Checking HTTPS..."
curl -s -o /dev/null -w "%{http_code}" https://$MONITORING_DOMAIN && echo " ✅ HTTPS working" || echo " ❌ HTTPS failed"

echo "Checking security headers..."
curl -sI https://$MONITORING_DOMAIN | grep -E "Strict-Transport|X-Frame|Content-Security" | wc -l | xargs -I {} test {} -ge 3 && echo "✅ Security headers present" || echo "⚠️  Some headers missing"
```

---

*This guide enables AI agents to perform fully automated deployments of the Secure Web Gateway. Always verify the deployment manually before production use.*
