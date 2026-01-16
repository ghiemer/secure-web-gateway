# 📋 Project Overview: Secure Web Gateway

## 🎯 Purpose

This project implements a **centralized, hardened gateway infrastructure** for Docker-based microservices. It serves as a reverse proxy with integrated security features and monitoring capabilities.

---

## 🏗️ Architecture Overview

```
                    ┌─────────────────────────────────────────────┐
                    │              INTERNET                        │
                    └────────────────────┬────────────────────────┘
                                         │
                                    Port 80/443
                                         │
                    ┌────────────────────▼────────────────────────┐
                    │           CADDY GATEWAY                      │
                    │   • Reverse Proxy                            │
                    │   • TLS Termination (Let's Encrypt)          │
                    │   • CrowdSec WAF Integration                 │
                    │   • Security Headers (HSTS, CSP, etc.)       │
                    │   • Rate Limiting (10 req/s per IP)          │
                    └───┬─────────────────────────────────────┬───┘
                        │                                     │
              mTLS      │                                     │  mTLS
                        │                                     │
         ┌──────────────▼─────────────┐    ┌─────────────────▼──────────────┐
         │    Backend Service A        │    │    Backend Service B            │
         │    (webapp_container)       │    │    (api_container)              │
         └────────────────────────────┘    └──────────────────────────────────┘
                        │
         ┌──────────────┼──────────────────────────────────────┐
         │              │           MONITORING STACK            │
         │   ┌──────────▼──────────┐                           │
         │   │     CROWDSEC        │◄──── Log Analysis          │
         │   │   Security Engine   │                           │
         │   └────────────────────┘                            │
         │                                                      │
         │   ┌────────────────────┐    ┌────────────────────┐  │
         │   │    PROMETHEUS      │◄───│     GRAFANA        │  │
         │   │   Metrics Store    │    │   Visualization    │  │
         │   └────────────────────┘    └────────────────────┘  │
         └─────────────────────────────────────────────────────┘
```

---

## 📁 File Analysis

### Root Directory

| File | Purpose | Technology |
|------|---------|------------|
| `docker-compose.yml` | Orchestrates all containers (Gateway, CrowdSec, Prometheus, Grafana) | Docker Compose |
| `Makefile` | Automates certificate generation, Caddyfile creation, secrets management | GNU Make, OpenSSL |
| `services.conf` | Defines backend services (Name, Domain, Host, Port) | Configuration File |
| `.env.example` | Template for environment variables | Environment File |
| `README.md` | Project documentation | Markdown |

---

### `/gateway/` - Caddy Reverse Proxy

| File | Purpose |
|------|---------|
| `Dockerfile` | Builds custom Caddy image with CrowdSec Bouncer and Transform Encoder plugins |
| `Caddyfile` | Main configuration: Routing, Security Headers, mTLS, Rate Limiting (auto-generated) |

**Implemented Security Features:**
- ✅ Automatic HTTPS (Let's Encrypt)
- ✅ Security Headers (HSTS, X-Frame-Options, CSP, etc.)
- ✅ CrowdSec Bouncer Integration (IP Blocking)
- ✅ Rate Limiting (10 req/s per IP)
- ✅ mTLS to Backend Services
- ✅ Server Header Removed
- ✅ Request Timeouts Configured

**Caddy Plugins:**
- `caddy-crowdsec-bouncer` - CrowdSec integration for IP blocking
- `transform-encoder` - Log transformation capabilities

---

### `/crowdsec/` - Intrusion Detection

| File | Purpose |
|------|---------|
| `acquis.yaml` | Data source configuration (reads Caddy access logs) |

**Function:**
- Analyzes Caddy logs in real-time
- Detects attack patterns (SQL Injection, Path Traversal, etc.)
- Provides blocklists for the Caddy Bouncer
- Uses community collections: `crowdsecurity/caddy`, `crowdsecurity/http-cve`

---

### `/prometheus/` - Metrics Collection

| File | Purpose |
|------|---------|
| `prometheus.yml` | Scrape configuration for Caddy metrics |

**Metrics Endpoint:** `gateway:2019`  
**Scrape Interval:** 15s  
**Retention:** 15 days

---

### `/grafana/` - Visualization

| File | Purpose |
|------|---------|
| `provisioning/datasources/datasource.yml` | Auto-configures Prometheus datasource |
| `provisioning/dashboards/provider.yml` | Dashboard auto-import configuration |
| `provisioning/dashboards/definitions/` | Placeholder for pre-configured dashboards |

---

### `/scripts/` - Utilities

| File | Purpose |
|------|---------|
| `backup.sh` | Backs up certificates, logs, and CrowdSec decisions |

---

### `/project-template/` - Boilerplate for New Services

| File | Purpose |
|------|---------|
| `docker-compose.yml` | Template: Service + internal Caddy with mTLS |
| `config/Caddyfile` | mTLS client authentication configuration |
| `README.md` | Detailed guide for connecting projects |

**Concept:** Backend services run their own Caddy which:
1. Only accepts encrypted connections from the Gateway
2. Validates Gateway's client certificate (mTLS)
3. Does NOT expose any external ports

---

## 🔄 Workflow: `make run`

```
┌─────────────────────────────────────────────────────────────────┐
│  1. SECRETS GENERATION (generate-secrets)                       │
├─────────────────────────────────────────────────────────────────┤
│  • Creates .env from .env.example (if not exists)               │
│  • Generates secure Grafana password                            │
│  • Creates docker-compose.override.yml for local customizations │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. PRE-FLIGHT CHECKS (preflight)                               │
├─────────────────────────────────────────────────────────────────┤
│  • Validates .env file exists                                   │
│  • Checks CROWDSEC_BOUNCER_API_KEY is set                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  3. CERTIFICATE GENERATION (certs)                              │
├─────────────────────────────────────────────────────────────────┤
│  • Root CA (5 years, RSA 4096) - if not exists                  │
│  • Gateway Client Cert (1 year, RSA 4096) - if not exists       │
│  • Service Certs (1 year, ECC P-256) - for each in services.conf│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  4. CADDYFILE GENERATION (caddyfile)                            │
├─────────────────────────────────────────────────────────────────┤
│  • Global Options (Email, Timeouts, PKI)                        │
│  • Security Snippets (Headers, Rate Limit, CrowdSec, Logging)   │
│  • Service Blocks (Loop over services.conf)                     │
│  • Monitoring Block (if MONITORING_DOMAIN set)                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  5. DOCKER COMPOSE UP                                           │
├─────────────────────────────────────────────────────────────────┤
│  • Starts: gateway, crowdsec, prometheus, grafana               │
│  • Network: gateway_net (Bridge)                                │
│  • Health checks for all services                               │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🌐 Network Topology

| Network | Type | Purpose |
|---------|------|---------|
| `gateway_net` | Bridge | Connects Gateway with all services |

**Port Mapping:**

| Container | Internal Ports | External Ports |
|-----------|----------------|----------------|
| Gateway | 80, 443, 2019 | 80, 443 |
| CrowdSec | 8080 | - (internal only) |
| Prometheus | 9090 | - (internal only) |
| Grafana | 3000 | - (via Gateway) |

---

## 📊 Container Summary

| Service | Image | Purpose | Health Check |
|---------|-------|---------|--------------|
| gateway | Custom (Caddy + Plugins) | Reverse Proxy, TLS, WAF | `wget http://127.0.0.1:2019/metrics` |
| crowdsec | crowdsecurity/crowdsec:v1.6.0 | Log Analysis, IP Blocking | `cscli version` |
| prometheus | prom/prometheus:v2.45.0 | Metrics Storage | `wget http://localhost:9090/-/healthy` |
| grafana | grafana/grafana:10.0.0 | Dashboards, Visualization | `wget http://localhost:3000/api/health` |

---

## 🔐 Security Architecture

### TLS Flow
```
Client ──HTTPS──▶ Gateway ──mTLS──▶ Backend Service
         │                    │
    Let's Encrypt        Internal CA
    (Public Cert)     (Gateway validates
                       Backend cert AND
                       Backend validates
                       Gateway client cert)
```

### mTLS Components
- **Root CA:** `certs/ca.crt` - Signs all internal certificates
- **Gateway Client Cert:** `certs/gateway-client.crt` - Gateway identifies itself to backends
- **Service Certs:** `certs/<host>.crt` - Backends identify themselves to Gateway

---

## 📝 Files Generated by Makefile

| File | Generated When | Regenerated On |
|------|----------------|----------------|
| `.env` | First `make run` | Never (manual) |
| `docker-compose.override.yml` | First `make run` | Never (manual) |
| `certs/ca.crt` | First `make certs` | Never (unless deleted) |
| `certs/gateway-client.crt` | First `make certs` | Never (unless deleted) |
| `certs/<service>.crt` | When service added | Never (unless deleted) |
| `gateway/Caddyfile` | Every `make caddyfile` | Every `make run` |

---

## 📚 Related Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Quick start guide |
| [project-template/README.md](project-template/README.md) | Guide for connecting new projects |
| [SECURITY-REPORT.md](SECURITY-REPORT.md) | Security audit findings |
