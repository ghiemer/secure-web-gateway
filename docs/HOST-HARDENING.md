# 🔒 Host Hardening Guide (SEC-010)

This document provides recommendations for securing the host system running the Secure Web Gateway.

> **Note:** The gateway only protects web traffic. Host-level security must be configured separately.

---

## 🛡️ Firewall Configuration

### UFW (Ubuntu/Debian)

```bash
# Reset and enable UFW
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (restrict to your IP if possible)
sudo ufw allow from YOUR_IP to any port 22

# Allow HTTP/HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp

# Enable firewall
sudo ufw enable
sudo ufw status verbose
```

### firewalld (RHEL/CentOS/Fedora)

```bash
# Set default zone
sudo firewall-cmd --set-default-zone=drop

# Allow SSH
sudo firewall-cmd --permanent --add-service=ssh

# Allow HTTP/HTTPS
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https

# Reload
sudo firewall-cmd --reload
sudo firewall-cmd --list-all
```

---

## 🔐 SSH Hardening

### /etc/ssh/sshd_config

```bash
# Disable root login
PermitRootLogin no

# Disable password authentication (use keys only)
PasswordAuthentication no
PubkeyAuthentication yes

# Limit users
AllowUsers your_username

# Disable empty passwords
PermitEmptyPasswords no

# Use strong ciphers
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512

# Restart SSH
sudo systemctl restart sshd
```

---

## 🚫 Fail2Ban / CrowdSec SSH Protection

### Option A: CrowdSec for SSH (Recommended)

```bash
# Install CrowdSec SSH collection on the HOST (not in Docker)
sudo cscli collections install crowdsecurity/sshd

# Verify
sudo cscli collections list | grep ssh
```

### Option B: Fail2Ban

```bash
# Install
sudo apt install fail2ban  # Debian/Ubuntu
sudo dnf install fail2ban  # RHEL/Fedora

# Configure /etc/fail2ban/jail.local
cat << 'EOF' | sudo tee /etc/fail2ban/jail.local
[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

# Enable and start
sudo systemctl enable fail2ban
sudo systemctl start fail2ban
sudo fail2ban-client status sshd
```

---

## 🔄 Automatic Security Updates

### Ubuntu/Debian

```bash
# Install unattended-upgrades
sudo apt install unattended-upgrades

# Configure
sudo dpkg-reconfigure -plow unattended-upgrades

# Verify
cat /etc/apt/apt.conf.d/20auto-upgrades
```

### RHEL/CentOS/Fedora

```bash
# Install dnf-automatic
sudo dnf install dnf-automatic

# Enable security updates only
sudo sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
sudo sed -i 's/upgrade_type = default/upgrade_type = security/' /etc/dnf/automatic.conf

# Enable timer
sudo systemctl enable --now dnf-automatic.timer
```

---

## 📊 System Auditing

### auditd

```bash
# Install
sudo apt install auditd  # Debian/Ubuntu
sudo dnf install audit   # RHEL/Fedora

# Add rules for Docker
cat << 'EOF' | sudo tee -a /etc/audit/rules.d/docker.rules
-w /usr/bin/docker -p rwxa -k docker
-w /var/lib/docker -p rwxa -k docker
-w /etc/docker -p rwxa -k docker
-w /usr/lib/systemd/system/docker.service -p rwxa -k docker
EOF

# Reload rules
sudo augenrules --load
sudo systemctl restart auditd
```

---

## 🐳 Docker Hardening

### /etc/docker/daemon.json

```json
{
  "icc": false,
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "no-new-privileges": true,
  "userland-proxy": false,
  "live-restore": true
}
```

```bash
# Apply changes
sudo systemctl restart docker
```

---

## ✅ Security Checklist

- [ ] Firewall configured (only ports 22, 80, 443 open)
- [ ] SSH hardened (key-only, no root login)
- [ ] Fail2Ban or CrowdSec SSH protection enabled
- [ ] Automatic security updates configured
- [ ] Docker daemon hardened
- [ ] System auditing enabled
- [ ] Non-root user for daily operations
- [ ] Regular security scans (Lynis, OpenSCAP)

---

## 🔍 Security Scanning

### Lynis

```bash
# Install
sudo apt install lynis  # or download from cisofy.com

# Run audit
sudo lynis audit system

# Review report
cat /var/log/lynis-report.dat
```

---

*This guide complements the Secure Web Gateway. The gateway protects web applications; this guide protects the host.*
