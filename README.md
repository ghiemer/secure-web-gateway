# 🛡️ Hardened Web Gateway Infrastructure

This infrastructure provides a centralized, secure gateway for all Docker projects, implementing security best practices (CrowdSec, Rate-Limiting, Security Headers) along with monitoring capabilities.

## 📂 Structure

*   `gateway/`: Contains Caddy configuration and custom Dockerfile (Caddy + Security Plugins).
*   `crowdsec/`: Configuration for the security engine.
*   `grafana/` & `prometheus/`: Monitoring stack configuration and provisioning.
*   `project-template/`: Template for connecting new projects to this gateway.

## 🚀 Installation & Configuration (Clone & Run)

We use a **"Make & Run"** workflow with automated pre-flight checks.

### 1. Configuration (`services.conf`)

Open `services.conf` and add your services (space-separated):

```text
# ServiceName    PublicDomain          InternalHost       InternalPort
web-app          app.your-domain.com   webapp_container   8080
api-service      api.your-domain.com   api_container      9000
```

*   `InternalHost`: The container name of your service in the Docker network.

### 2. Initial Setup

On first `make run`, a `.env` file is automatically created from `.env.example` with:
*   🔐 **Secure Grafana password** (auto-generated)

Then adjust the `.env` file:
```bash
GATEWAY_EMAIL=admin@your-domain.com
MONITORING_DOMAIN=monitor.your-domain.com
```

### 3. Generate CrowdSec API Key (required!)

⚠️ **Important:** The CrowdSec Bouncer requires an API key. On first startup:

```bash
# 1. Start CrowdSec first
docker compose up -d crowdsec

# 2. Generate API key
docker exec gateway_crowdsec cscli bouncers add gateway-bouncer

# 3. Add key to .env
CROWDSEC_BOUNCER_API_KEY=<generated-key>

# 4. Start complete stack
make run
```

### 4. Start

```bash
make run
```

The script automatically performs:
1.  ✅ **Pre-Flight Checks** (Validates .env and API keys)
2.  ✅ **Secrets Generation** (Grafana password if not present)
3.  ✅ **Certificates** (Root CA 5 years, Server Certs 1 year, ECC-based)
4.  ✅ **Caddyfile** (Routing, Security Headers, CSP, mTLS, Timeouts)
5.  ✅ **Docker Stack** (with health checks for all services)

## 📊 Monitoring Access

*   **Grafana**: `https://<MONITORING_DOMAIN>` (e.g., `https://monitor.your-domain.com`)
*   **Login**: User `admin`, password was generated during initial setup (see `.env`)
*   **Prometheus**: Only accessible internally, pre-configured as datasource in Grafana
*   **Recommended Dashboard**: Caddy Dashboard (ID: 13460)

> **Note:** Grafana is not directly accessible via port 3000, but exclusively through the gateway with TLS.

## 🔧 Available Make Targets

| Command | Description |
|---------|-------------|
| `make run` | Full build & start |
| `make certs` | Generate certificates only |
| `make caddyfile` | Regenerate Caddyfile only |
| `make clean` | Delete certificates and Caddyfile |
| `make preflight` | Run pre-flight checks manually |

## 🔌 Connecting New Projects

See the `project-template/` folder. The principle is always:
1.  Connect container to the `gateway_net` network.
2.  Do not expose any ports externally.
3.  Generate and integrate mTLS certificates.
4.  Add service to `services.conf` and run `make run`.

## 🛡️ Security Features

- **TLS/HTTPS**: Automatic via Let's Encrypt
- **mTLS**: Mutual TLS between gateway and backend services
- **WAF**: CrowdSec with community collections (Caddy, HTTP-CVE)
- **Rate Limiting**: 10 requests/second per IP
- **Security Headers**: HSTS, CSP, X-Frame-Options, etc.
- **Container Hardening**: `no-new-privileges` on all containers
- **Health Checks**: Automatic monitoring of all services
