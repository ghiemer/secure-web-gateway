# 🔌 Project Template for Secure Web Gateway

This template helps you connect a new project to the **Secure Web Gateway** infrastructure.

## 📋 Overview: How the Gateway Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              INTERNET                                        │
└──────────────────────────────────┬──────────────────────────────────────────┘
                                   │
                          HTTPS (Port 443)
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         SECURE WEB GATEWAY                                   │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                      CADDY (Reverse Proxy)                          │    │
│  │  • TLS Termination (Let's Encrypt)                                  │    │
│  │  • Security Headers (HSTS, CSP, X-Frame-Options)                    │    │
│  │  • Rate Limiting (10 req/s per IP)                                  │    │
│  │  • CrowdSec WAF Integration                                         │    │
│  └───────────────────────────────┬─────────────────────────────────────┘    │
│                                  │                                           │
│                        mTLS (Mutual TLS)                                     │
│                    Gateway authenticates to Project                          │
│                    Project verifies Gateway certificate                      │
│                                  │                                           │
└──────────────────────────────────┼──────────────────────────────────────────┘
                                   │
                            gateway_net
                          (Docker Network)
                                   │
                                   ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         YOUR PROJECT                                         │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    PROJECT CADDY (Internal)                          │    │
│  │  • Receives mTLS connection from Gateway                            │    │
│  │  • Verifies Gateway's client certificate                            │    │
│  │  • NO external ports exposed                                        │    │
│  └───────────────────────────────┬─────────────────────────────────────┘    │
│                                  │                                           │
│                            HTTP (internal)                                   │
│                                  │                                           │
│                                  ▼                                           │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                     YOUR APPLICATION                                 │    │
│  │                   (Node.js, Python, Go, etc.)                        │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

## 🔐 Security Flow

1. **Client Request** → `https://app.yourdomain.com`
2. **Gateway receives** → TLS termination, CrowdSec checks IP, applies rate limit
3. **Gateway forwards** → mTLS connection to your project's internal Caddy
4. **Project Caddy verifies** → Gateway's client certificate against CA
5. **Project Caddy forwards** → Plain HTTP to your application (internal network only)
6. **Response flows back** → Through the same secure chain

## 🚀 Adding a New Project

### Step 1: Copy the Template

```bash
# From the gateway directory
cp -r project-template /path/to/your/new-project

# Or create a new project directory
mkdir -p /path/to/your/new-project
cp -r project-template/* /path/to/your/new-project/
```

### Step 2: Register Service in Gateway

Edit `services.conf` in the **gateway repository**:

```text
# ServiceName    PublicDomain              InternalHost        InternalPort
my-app           myapp.yourdomain.com      myapp_caddy         443
```

| Field | Description |
|-------|-------------|
| `ServiceName` | Unique identifier (no spaces) |
| `PublicDomain` | The public domain for this service |
| `InternalHost` | Container name of your project's Caddy |
| `InternalPort` | Always `443` (mTLS) |

### Step 3: Generate Certificates

Run from the **gateway repository**:

```bash
make certs
```

This generates:
- `certs/<InternalHost>.crt` - Server certificate for your project
- `certs/<InternalHost>.key` - Private key for your project

### Step 4: Configure Your Project

#### 4.1 Update `docker-compose.yml`

```yaml
services:
  caddy:
    image: caddy:2.7-alpine
    container_name: myapp_caddy  # Must match InternalHost in services.conf
    restart: unless-stopped
    environment:
      - DOMAIN=myapp.yourdomain.com
    volumes:
      - ./config/Caddyfile:/etc/caddy/Caddyfile
      - /path/to/gateway/certs:/certs:ro  # Mount gateway's certs directory
    networks:
      - internal
      - gateway_net
    depends_on:
      - app
    security_opt:
      - no-new-privileges:true

  app:
    image: your-app-image
    networks:
      - internal
    security_opt:
      - no-new-privileges:true
    # NO ports exposed!

networks:
  gateway_net:
    external: true
  internal:
    driver: bridge
```

#### 4.2 Update `config/Caddyfile`

```caddyfile
{
    auto_https off
}

https://{$DOMAIN} {
    tls /certs/myapp_caddy.crt /certs/myapp_caddy.key {
        client_auth {
            mode require_and_verify
            trusted_ca_cert_file /certs/ca.crt
        }
    }

    reverse_proxy app:8080  # Your app's internal port
}
```

### Step 5: Regenerate Gateway Config & Start

```bash
# In gateway repository
make run

# In your project directory
docker compose up -d
```

## 📁 File Structure

```
your-project/
├── docker-compose.yml      # Your project's Docker Compose
├── config/
│   └── Caddyfile          # Internal Caddy mTLS config
├── src/                   # Your application source
└── ...
```

## ⚠️ Important Rules

1. **Never expose ports** - Your app containers should NOT have `ports:` mapping
2. **Always use gateway_net** - Your Caddy must join the `gateway_net` network
3. **Container naming** - The `container_name` must match `InternalHost` in services.conf
4. **Certificate paths** - Mount the gateway's `certs/` directory read-only

## 🔄 Updating an Existing Project

If you need to change the domain or configuration:

1. Update `services.conf` in the gateway repository
2. Delete the old certificate: `rm certs/<old_host>.crt certs/<old_host>.key`
3. Run `make run` in the gateway repository
4. Update your project's Caddyfile with new certificate paths
5. Restart your project: `docker compose restart`

## 🆘 Troubleshooting

### Connection Refused
- Check if your project's Caddy container is running
- Verify the container name matches `InternalHost`
- Ensure `gateway_net` network exists: `docker network ls`

### Certificate Errors
- Verify certificates exist: `ls -la /path/to/gateway/certs/`
- Check certificate permissions (readable by Caddy user)
- Ensure CA certificate is mounted correctly

### 502 Bad Gateway
- Your app container might not be running
- Check internal port in Caddyfile matches your app's port
- Verify internal network connectivity

### View Gateway Logs
```bash
docker logs gateway -f
```

### View Your Project's Caddy Logs
```bash
docker logs myapp_caddy -f
```

## 📝 Example: Full Working Setup

### services.conf (Gateway)
```text
blog    blog.example.com    blog_caddy    443
api     api.example.com     api_caddy     443
```

### docker-compose.yml (Blog Project)
```yaml
services:
  caddy:
    image: caddy:2.7-alpine
    container_name: blog_caddy
    volumes:
      - ./config/Caddyfile:/etc/caddy/Caddyfile
      - ../secure-web-gateway/certs:/certs:ro
    networks:
      - internal
      - gateway_net
    depends_on:
      - ghost
    security_opt:
      - no-new-privileges:true

  ghost:
    image: ghost:5-alpine
    environment:
      - url=https://blog.example.com
    networks:
      - internal

networks:
  gateway_net:
    external: true
  internal:
    driver: bridge
```

### config/Caddyfile (Blog Project)
```caddyfile
{
    auto_https off
}

https://blog.example.com {
    tls /certs/blog_caddy.crt /certs/blog_caddy.key {
        client_auth {
            mode require_and_verify
            trusted_ca_cert_file /certs/ca.crt
        }
    }

    reverse_proxy ghost:2368
}
```
