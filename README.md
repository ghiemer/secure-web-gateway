# 🛡️ Hardened Web Gateway Infrastructure

This infrastructure provides a centralized, secure gateway for all Docker projects, implementing security best practices (CrowdSec, Rate-Limiting, Security Headers) along with monitoring capabilities.

> 🤖 **AI Agents:** For automated deployment instructions, see [docs/AI-AGENT-DEPLOY.md](docs/AI-AGENT-DEPLOY.md)

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
3.  ✅ **Override File** (Creates docker-compose.override.yml for local customizations)
4.  ✅ **Certificates** (Root CA 5 years, Server Certs 1 year, ECC-based)
5.  ✅ **Caddyfile** (Routing, Security Headers, CSP, mTLS, Timeouts)
6.  ✅ **Docker Stack** (with health checks for all services)

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

### Maintenance Scripts

| Script | Description |
|--------|-------------|
| `./scripts/check-certs.sh` | Check certificate expiry dates |
| `./scripts/backup.sh` | Create encrypted backup |

```bash
# Check certificate expiry (warns if < 30 days)
./scripts/check-certs.sh

# Create encrypted backup
ENCRYPT=true BACKUP_PASSWORD=secret ./scripts/backup.sh
```

## 🔌 Connecting New Projects

See the `project-template/` folder. The principle is always:
1.  Connect container to the `gateway_net` network.
2.  Do not expose any ports externally.
3.  Generate and integrate mTLS certificates.
4.  Add service to `services.conf` and run `make run`.

## ⚙️ Server-Specific Configuration

The `docker-compose.override.yml` file (created on first `make run`) allows server-specific customizations without modifying the main `docker-compose.yml`:

```yaml
# Example: Expose Grafana directly for debugging
services:
  grafana:
    ports:
      - "3000:3000"

# Example: Add resource limits
  gateway:
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M

# Example: Add your own service
  myapp:
    image: myapp:latest
    container_name: myapp_container
    networks:
      - gateway_net
```

This file is:
- ✅ **Auto-merged** with docker-compose.yml by Docker Compose
- ✅ **Ignored by git** - your changes stay local
- ✅ **Preserved on updates** - `git pull` won't affect it

## 🛡️ Security Features

- **TLS/HTTPS**: Automatic via Let's Encrypt
- **mTLS**: Mutual TLS between gateway and backend services
- **WAF**: CrowdSec with community collections (Caddy, HTTP-CVE)
- **Rate Limiting**: 10 requests/second per IP
- **Security Headers**: HSTS, CSP, X-Frame-Options, etc.
- **Container Hardening**: `no-new-privileges` on all containers
- **Health Checks**: Automatic monitoring of all services

## 🔄 Updating the Gateway

When pulling updates from the repository, your local configuration is preserved:

### Files that are safe (auto-generated)
These files are in `.gitignore` and will not cause conflicts:
- `.env` - Your local environment configuration
- `docker-compose.override.yml` - Server-specific Docker customizations
- `certs/` - Generated certificates
- `gateway/Caddyfile` - Generated from Makefile

### Protecting services.conf from conflicts

If you've customized `services.conf`, protect it from git conflicts:

```bash
# Tell git to ignore local changes to services.conf
git update-index --skip-worktree services.conf

# To re-enable tracking (if you want to commit changes)
git update-index --no-skip-worktree services.conf
```

### Update Workflow

```bash
# 1. Pull latest changes
git pull origin main

# 2. Regenerate configuration (certificates are kept if valid)
make caddyfile

# 3. Restart with new configuration
make run
```

### Adding a New Service (After Update)

When adding a new project after updating:

```bash
# 1. Add entry to services.conf
echo "myapp    myapp.example.com    myapp_caddy    443" >> services.conf

# 2. Generate certificate and rebuild Caddyfile
make run
```

The Makefile handles incremental updates:
- **Existing certificates** are preserved (only new services get new certs)
- **Caddyfile** is regenerated on each `make caddyfile` or `make run`
- **Docker containers** are updated with `--remove-orphans`

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | This file - Quick start guide |
| [docs/OVERVIEW.md](docs/OVERVIEW.md) | Architecture overview & diagrams |
| [docs/SECURITY-REPORT.md](docs/SECURITY-REPORT.md) | Security audit findings & status |
| [docs/HOST-HARDENING.md](docs/HOST-HARDENING.md) | Host-level security guide |
| [docs/AI-AGENT-DEPLOY.md](docs/AI-AGENT-DEPLOY.md) | 🤖 AI Agent deployment guide |
| [project-template/README.md](project-template/README.md) | Guide for connecting new projects |

---

## ⚠️ Security Audit Disclaimer

The security audit documented in [docs/SECURITY-REPORT.md](docs/SECURITY-REPORT.md) was performed using **GitHub Copilot with Claude Opus 4.5**.

**DISCLAIMER:**  
This automated security analysis is provided "as is" without warranty of any kind. The findings are intended as guidance and do not constitute a comprehensive professional security audit. **No liability is accepted** for any damages, security breaches, or issues arising from the use of this analysis or the implementation of its recommendations.

For production environments handling sensitive data, a manual security review by qualified security professionals is strongly recommended.

---

## 📄 License

MIT License

Copyright (c) 2026

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
