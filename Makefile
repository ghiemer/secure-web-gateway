include .env

# Directories
CERT_DIR := certs
DATA_DIR := data

# Shell settings
SHELL := /bin/bash

.PHONY: all clean certs caddyfile run

all: certs caddyfile

# 0. Pre-Flight Checks & Secrets
generate-secrets:
	@if [ ! -f .env ]; then \
		echo "Creating .env with secure passwords..."; \
		cp .env.example .env; \
		GRAFANA_PW=$$(openssl rand -base64 24); \
		if [[ "$$OSTYPE" == "darwin"* ]]; then \
			sed -i '' "s|GRAFANA_PASSWORD=admin|GRAFANA_PASSWORD=$$GRAFANA_PW|" .env; \
		else \
			sed -i "s|GRAFANA_PASSWORD=admin|GRAFANA_PASSWORD=$$GRAFANA_PW|" .env; \
		fi; \
		echo "Grafana password generated: $$GRAFANA_PW"; \
	fi

preflight:
	@echo "--- Pre-Flight Checks ---"
	@if [ ! -f .env ]; then \
		echo "❌ ERROR: .env not found. Run 'make run' to create it."; \
		exit 1; \
	fi
	@# Load .env variables for check
	@export $$(cat .env | xargs) && \
	if [ -z "$$CROWDSEC_BOUNCER_API_KEY" ]; then \
		echo "❌ ERROR: CROWDSEC_BOUNCER_API_KEY is not set!"; \
		echo "Please add or generate the key."; \
		exit 1; \
	fi
	@echo "✅ Pre-Flight Checks passed."

# 1. Generate Certificates (CA, Client, and loop over Services)
certs: preflight
	@echo "--- Generating Certificates ---"
	@mkdir -p $(CERT_DIR)
	
	# A) Root CA (if not exists)
	@if [ ! -f $(CERT_DIR)/ca.key ]; then \
		echo "Creating Root CA..."; \
		openssl req -x509 -sha256 -nodes -days 1825 -newkey rsa:4096 \
		-keyout $(CERT_DIR)/ca.key -out $(CERT_DIR)/ca.crt \
		-subj "/CN=Gateway-Root-CA"; \
	fi

	# B) Gateway Client Cert (for Caddy -> Backend Auth)
	@if [ ! -f $(CERT_DIR)/gateway-client.key ]; then \
		echo "Creating Gateway Client Cert..."; \
		openssl req -new -newkey rsa:4096 -nodes \
		-keyout $(CERT_DIR)/gateway-client.key -out $(CERT_DIR)/gateway-client.csr \
		-subj "/CN=gateway-client"; \
		openssl x509 -req -in $(CERT_DIR)/gateway-client.csr \
		-CA $(CERT_DIR)/ca.crt -CAkey $(CERT_DIR)/ca.key -CAcreateserial \
		-out $(CERT_DIR)/gateway-client.crt -days 365 -sha256; \
	fi

	# C) Loop over services.conf for Server Certs
	@while read -r name domain host port; do \
		[[ "$$name" =~ ^#.* ]] && continue; \
		[[ -z "$$name" ]] && continue; \
		if [ ! -f $(CERT_DIR)/$$host.crt ]; then \
			echo "Creating cert for service: $$name ($$host)..."; \
			openssl ecparam -name prime256v1 -genkey -noout -out $(CERT_DIR)/$$host.key; \
			openssl req -new -key $(CERT_DIR)/$$host.key -out $(CERT_DIR)/$$host.csr \
			-subj "/CN=$$host"; \
			echo "subjectAltName=DNS:$$host,DNS:localhost" > $(CERT_DIR)/$$host.ext; \
			openssl x509 -req -in $(CERT_DIR)/$$host.csr \
			-CA $(CERT_DIR)/ca.crt -CAkey $(CERT_DIR)/ca.key -CAcreateserial \
			-out $(CERT_DIR)/$$host.crt -days 365 -sha256 \
			-extfile $(CERT_DIR)/$$host.ext; \
			rm $(CERT_DIR)/$$host.ext $(CERT_DIR)/$$host.csr; \
		fi \
	done < services.conf

# 2. Generate Caddyfile (Hardened)
caddyfile:
	@echo "--- Creating Hardened Caddyfile in gateway/ ---"
	@mkdir -p gateway
	@echo "{" > gateway/Caddyfile
	@echo "    # --- Global Options ---" >> gateway/Caddyfile
	@echo "    email $(GATEWAY_EMAIL)" >> gateway/Caddyfile
	@echo "    grace_period 5s" >> gateway/Caddyfile
	@echo "" >> gateway/Caddyfile
	@echo "    # Metrics for Prometheus and Timeouts" >> gateway/Caddyfile
	@echo "    servers {" >> gateway/Caddyfile
	@echo "        metrics" >> gateway/Caddyfile
	@echo "        timeouts {" >> gateway/Caddyfile
	@echo "            read_body 30s" >> gateway/Caddyfile
	@echo "            read_header 10s" >> gateway/Caddyfile
	@echo "            write 60s" >> gateway/Caddyfile
	@echo "            idle 120s" >> gateway/Caddyfile
	@echo "        }" >> gateway/Caddyfile
	@echo "    }" >> gateway/Caddyfile
	@echo "" >> gateway/Caddyfile
	@echo "    # Internal CA for mTLS" >> gateway/Caddyfile
	@echo "    pki {" >> gateway/Caddyfile
	@echo "        ca internal_ca {" >> gateway/Caddyfile
	@echo "            name \"Gateway Internal CA\"" >> gateway/Caddyfile
	@echo "        }" >> gateway/Caddyfile
	@echo "    }" >> gateway/Caddyfile
	@echo "}" >> gateway/Caddyfile
	@echo "" >> gateway/Caddyfile
	@echo "# --- CrowdSec Bouncer (Global) ---" >> gateway/Caddyfile
	@echo "(crowdsec) {" >> gateway/Caddyfile
	@echo "    crowdsec {" >> gateway/Caddyfile
	@echo "        api_url http://crowdsec:8080/" >> gateway/Caddyfile
	@echo "        api_key {\$$CROWDSEC_API_KEY}" >> gateway/Caddyfile
	@echo "        ticker_interval 15s" >> gateway/Caddyfile
	@echo "    }" >> gateway/Caddyfile
	@echo "}" >> gateway/Caddyfile
	@echo "" >> gateway/Caddyfile
	@echo "# --- Security Headers Snippet ---" >> gateway/Caddyfile
	@echo "(security_headers) {" >> gateway/Caddyfile
	@echo "    header {" >> gateway/Caddyfile
	@echo "        Strict-Transport-Security \"max-age=31536000; includeSubDomains; preload\"" >> gateway/Caddyfile
	@echo "        X-Frame-Options \"DENY\"" >> gateway/Caddyfile
	@echo "        X-Content-Type-Options \"nosniff\"" >> gateway/Caddyfile
	@echo "        Referrer-Policy \"strict-origin-when-cross-origin\"" >> gateway/Caddyfile
	@echo "        Permissions-Policy \"geolocation=(), microphone=(), camera=()\"" >> gateway/Caddyfile
	@echo "        Content-Security-Policy \"default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'self'; form-action 'self'\"" >> gateway/Caddyfile
	@echo "        Server \"Gateway\"" >> gateway/Caddyfile
	@echo "    }" >> gateway/Caddyfile
	@echo "}" >> gateway/Caddyfile

# ... (Previous context omitted) ...

	@# Methods Endpoint (Internal Only)
	@echo "127.0.0.1:2019 {" >> gateway/Caddyfile
	@echo "    metrics" >> gateway/Caddyfile
	@echo "}" >> gateway/Caddyfile
	@echo "" >> gateway/Caddyfile
	@# Monitoring Block (if configured)
	@if [ ! -z "$(MONITORING_DOMAIN)" ]; then \
		echo "" >> gateway/Caddyfile; \
		echo "$(MONITORING_DOMAIN) {" >> gateway/Caddyfile; \
		echo "    import crowdsec" >> gateway/Caddyfile; \
		echo "    import security_headers" >> gateway/Caddyfile; \
		echo "    import rate_limit" >> gateway/Caddyfile; \
		echo "    import logging" >> gateway/Caddyfile; \
		echo "" >> gateway/Caddyfile; \
		echo "    reverse_proxy gateway_grafana:3000" >> gateway/Caddyfile; \
		echo "}" >> gateway/Caddyfile; \
		echo "Monitoring configured at: $(MONITORING_DOMAIN)"; \
	fi
	@echo "Hardened Caddyfile created in gateway/."

# 3. Start
run: generate-secrets all
	@echo "--- Starting Docker Compose ---"
	docker compose up -d --remove-orphans

clean:
	rm -rf $(CERT_DIR) gateway/Caddyfile
