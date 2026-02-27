# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

OurChat is an enterprise LLM chat system deployment wrapper for LibreChat, designed to integrate AWS Bedrock with LDAP/AD authentication. This repository contains installation scripts, configuration templates, and management utilities - it does NOT contain the LibreChat application itself (which is cloned during installation).

**Architecture**: Docker Compose based deployment that orchestrates:
- LibreChat (API + Client) - cloned from github.com/danny-avila/LibreChat
- MongoDB (port 27017/27018) - chat history and user data
- Meilisearch - search indexing
- VectorDB - RAG capabilities
- NGINX - SSL termination and reverse proxy

## Core Commands

### Installation & Setup
```bash
# 1. Server preparation (as root or with sudo)
curl https://raw.githubusercontent.com/dirkpetersen/our-chat/main/prepare-server.sh | bash

# 2. After switching to ochat user (sudo su - ochat)
cd ~
git clone https://github.com/dirkpetersen/our-chat/
cp ~/our-chat/.env.ochat ~/.env
cp ~/our-chat/librechat.yaml ~/librechat.yaml
cp ~/our-chat/nginx-ourchat.conf ~/nginx-ourchat.conf

# 3. Configure AWS credentials
export AWS_ACCESS_KEY_ID=<key>
export AWS_SECRET_ACCESS_KEY=<secret>
export AWS_DEFAULT_REGION=<region>

# 4. Test AWS Bedrock connectivity
~/our-chat/tests/bedrock-test.py

# 5. Test LDAP configuration (optional)
~/our-chat/tests/ldap-test.py <testuser>

# 6. Install LibreChat
~/our-chat/install-librechat.sh
```

### Management
```bash
# Start/stop LibreChat
docker compose -f ~/LibreChat/deploy-compose-ourchat.yml up -d
docker compose -f ~/LibreChat/deploy-compose-ourchat.yml down

# Update LibreChat (preferred - use the update script in ~/bin)
~/bin/update-librechat.sh
# Logs written to ~/.logs/librechat-update.log

# Enable debug logging
vi ~/.env  # Set DEBUG_LOGGING=true
cp ~/.env ~/LibreChat/
docker compose -f ~/LibreChat/deploy-compose-ourchat.yml down
docker compose -f ~/LibreChat/deploy-compose-ourchat.yml up  # without -d to see logs

# Manual purge of old messages
~/our-chat/purge_old_messages.py
```

### ~/bin/update-librechat.sh
The `ochat` user has an update script at `~/bin/update-librechat.sh` (not in this repo). It performs a full update cycle with logging and verification:
1. Validates running as non-root user in the `docker` group
2. `docker compose down` → `git pull` → `docker compose pull` → `docker compose up -d`
3. Waits 5 seconds then verifies containers show `Up` status
4. Prunes **all** unused Docker images (`docker image prune -a --force`) to reclaim disk
5. Logs all steps with timestamps to `~/.logs/librechat-update.log`

**Note**: Uses `error_exit` on any failure — the update halts rather than leaving containers in a partial state.

### ochat Crontab
```cron
@reboot /usr/bin/docker compose -f /home/ochat/LibreChat/deploy-compose-ourchat.yml up -d
22 2 * * * "/home/ochat/our-chat/purge_old_messages.py" > ~/purge_old_messages.log 2>&1

# first saturday night every month, 5am PT, 1PM UTC
#5 13 * * 6 [ $(date +\%d) -le 7 ] && /home/ochat/bin/update-ochat-and-cert.sh > ~/update-ochat-and-cert.log 2>&1

#33 3 * * * "/home/ochat/bin/update-librechat.sh"
```

The last two entries are kept commented out — enable them only when automated updates are appropriate for the deployment:
- `~/bin/update-ochat-and-cert.sh`: runs the first Saturday of each month at 5am PT, combines a LibreChat update with SSL certificate renewal
- `~/bin/update-librechat.sh`: daily at 3:33am; commented because unattended nightly updates may not be appropriate in all environments

### ~/bin/update-ochat-and-cert.sh
Monthly cert renewal + update script (not in this repo, belongs at `~/bin/update-ochat-and-cert.sh`). Currently misplaced at `~/update-ochat-and-cert.sh` — should be moved:
```bash
mv ~/update-ochat-and-cert.sh ~/bin/
```

What it does: `docker compose down` → `git pull` → `docker compose pull` → **`sudo certbot renew --quiet`** → `docker compose up -d`

Unlike `update-librechat.sh`, this script has no error handling or logging — failures are only captured if the cron job redirects output. Requires the `ochat` user to have passwordless sudo for `/usr/bin/certbot`.

## Key Configuration Files

### .env.ochat (template copied to ~/.env)
- Primary configuration copied to ~/LibreChat/.env during installation via `envsubst` - `${AWS_ACCESS_KEY_ID}`, `${AWS_SECRET_ACCESS_KEY}`, `${AWS_DEFAULT_REGION}` are expanded from shell environment at install time
- AWS Bedrock credentials: `BEDROCK_AWS_ACCESS_KEY_ID`, `BEDROCK_AWS_SECRET_ACCESS_KEY`, `BEDROCK_AWS_DEFAULT_REGION`
- LDAP settings: `LDAP_URL`, `LDAP_BIND_DN`, `LDAP_SEARCH_FILTER`, etc.
- Security tokens: `CREDS_KEY`, `CREDS_IV`, `JWT_SECRET`, `JWT_REFRESH_SECRET`, `MEILI_MASTER_KEY` — the values in `.env.ochat` are **examples only** and must be regenerated
- Generate tokens at: https://www.librechat.ai/toolkit/creds_generator

### librechat.yaml
- LibreChat-specific configuration
- Terms of service modal with usage policy
- Registration restrictions (allowedDomains: university.edu)
- Bedrock endpoint configuration (streamRate, titleModel, availableRegions)
- Custom endpoints for on-prem LLMs (Llama-CPP examples commented out)
- File upload limits

### nginx-ourchat.conf
- SSL certificate paths: `/etc/librechat/ssl/our-chat.pem`, `/etc/librechat/ssl/our-chat.pw`
- Or Let's Encrypt: `/etc/letsencrypt/live/${FQDN}/fullchain.pem`
- HTTP to HTTPS redirect on port 80
- TLS 1.2/1.3 with Mozilla intermediate cipher suite
- Security headers: HSTS, X-Content-Type-Options, Cache-Control
- Client max body size: 25MB (for file uploads)
- Reverse proxy to LibreChat API on port 3080

## Important Scripts

### install-librechat.sh
Main installation script that:
1. Installs Docker Compose plugin if needed
2. Clones LibreChat from GitHub to ~/LibreChat
3. Creates `deploy-compose-ourchat.yml` by deriving it from LibreChat's `deploy-compose.yml` via `sed` (not in this repo): exposes MongoDB port 27018, adds SSL cert volume mount, switches nginx config to `nginx-ourchat.conf`
4. Copies config files from ~/ to ~/LibreChat/
5. Activates SSL certificates (Certbot or custom)
6. Sets up cron jobs:
   - `@reboot` - auto-start LibreChat
   - `22 2 * * *` - daily purge of old messages
   - (commented) monthly cert renewal + update, and daily `update-librechat.sh` — see [ochat Crontab](#ochat-crontab)
7. Creates systemd user service for dev mode (librechat-backend.service)
8. Installs AWS CLI v2 if not present

**Key behavior**: `envsubst` expands `${AWS_*}` environment variables when copying ~/.env to ~/LibreChat/.env; the expanded copy is also written back to ~/.env.

### bedrock-model-list.py
Utility to generate the `BEDROCK_AWS_MODELS` string for `.env` by live-testing which models are available in your AWS account. Tests each model with `us.`, `global.`, and no prefix to find the correct invocation form (matching what LibreChat uses).

```bash
# Basic usage - outputs BEDROCK_AWS_MODELS=... line
python3 bedrock-model-list.py

# Place specific models first, ignore embedding/image models, verbose output
python3 bedrock-model-list.py \
  --first "us.anthropic.claude-3-5-sonnet-20241022-v2:0" \
  --ignore "amazon.titan-embed,amazon.titan-image,cohere.embed,stability" \
  --region us-west-2 \
  --verbose

# Output formats: env (default), list, yaml
python3 bedrock-model-list.py --format list

# --loose skips streaming validation (faster but less accurate)
# Default mode uses invoke_model_with_response_stream (strict) to match LibreChat behavior
```

Key logic: `--first` models are always included without testing (user pre-validates them); `--ignore` patterns do NOT apply to `--first` models. Handles per-provider payload formats (Anthropic, Meta, Amazon Nova, Amazon Titan, AI21, Cohere, Mistral).

### prepare-server.sh
Server setup script (requires root/sudo) that:
1. Installs OS packages: docker, vim, git, certbot, python3-pip, python3-boto3, python3-pymongo, python3-ldap3
2. Installs Docker CE from docker.com repositories
3. Creates `ochat` user with home directory (on largest filesystem if not /)
4. Enables systemd lingering for ochat user
5. Adds ochat to docker group
6. Optionally configures Let's Encrypt if server has public port 80 access

**Note**: If largest filesystem is not `/`, docker data-root is moved there via /etc/docker/daemon.json

### purge_old_messages.py
Data retention script (runs daily at 2:22 AM via cron):
- Connects to MongoDB on localhost:27018
- Deletes messages and files older than DAYSAGO (default: 180 days)
- Required for regulatory compliance in healthcare environments
- Dependencies: pymongo

### tests/bedrock-test.py
AWS Bedrock connectivity test:
- Writes AWS credentials to ~/.aws/credentials and ~/.aws/config (only if [default] section doesn't already exist)
- Lists available Bedrock models
- Sends "Hello, world" test prompt to first available Anthropic model
- Must succeed before installation

### tests/ldap-test.py
LDAP configuration validator:
- Loads LDAP settings from ~/.env
- Tests connection to LDAP server
- Evaluates LDAP_SEARCH_FILTER with provided test username
- Shows matched user's DN and attributes (displayName, memberOf)
- Required before enabling LDAP authentication

## Authentication & Authorization

### LDAP/AD Integration
**Phase 1 (Pilot - through November 2026)**: Just-In-Time (JIT) user creation on first login. Access controlled by domain restriction in librechat.yaml and ToS acceptance. `LDAP_SEARCH_FILTER` uses simple username match: `(sAMAccountName={{username}})`

**Phase 2 (Production - December 2026+)**: Optionally add group-based authorization. Example OR-logic filter for multiple groups:
```
(&(sAMAccountName={{username}})(|(memberOf=CN=ochat-all-users,...)(memberOf=CN=ochat-supercomputer-users,...)))
```

**Known limitation**: Non-members receive 401 (AuthN) instead of 403 (AuthZ) — upstream LibreChat issue.

- `LDAP_LOGIN_USES_USERNAME=true` allows login with username instead of full email
- Test with: `~/our-chat/tests/ldap-test.py <username>`

### Email Domain Restriction (Alternative to LDAP)
Set in librechat.yaml:
```yaml
registration:
  allowedDomains:
    - "university.edu"
```

## AWS Bedrock Configuration

### Credentials Management
- Service account needs ONLY AmazonBedrockFullAccess policy
- Credentials stored in ~/.aws/ (created by bedrock-test.py)
- Also set in ~/.env as BEDROCK_AWS_* variables
- AWS CLI v2 installed automatically if missing
- ~/.awsrc sources credentials into shell environment

### Model Access
- Some models require explicit authorization per AWS account (EULA acceptance)
- Test access with: `~/our-chat/tests/bedrock-test.py`
- Use `bedrock-model-list.py` to auto-generate the correct `BEDROCK_AWS_MODELS` value
- Unsupported models:
  - No streaming: ai21.j2-mid-v1
  - No conversation history: ai21.j2-ultra-v1, cohere.command-text-v14, cohere.command-light-text-v14

### Multi-Region Support
Optional in librechat.yaml:
```yaml
endpoints:
  bedrock:
    availableRegions:
      - "us-west-1"
      - "us-west-2"
```

## SSL Certificate Handling

### Option 1: Enterprise Certificates (PKCS12)
```bash
openssl pkcs12 -in cert-from-IT.pfx -out ~/our-chat.pem
# Leave space before echo to avoid bash history:
 echo "your-pem-passphrase" > ~/our-chat.pw
chmod 600 ~/our-chat.*
```

### Option 2: Let's Encrypt
- Server must be reachable on public port 80
- FQDN prompted during prepare-server.sh or install-librechat.sh
- Automatically activates in nginx-ourchat.conf
- Mounts /etc/letsencrypt into NGINX container

## Data Management

### MongoDB Connection
- Internal port: 27017 (container)
- External port: 27018 (host for maintenance)
- Database: LibreChat
- Collections: messages, files

### Backup Requirements (DR/BC)
Only these 5 files need secure backup:
1. ~/.env
2. ~/librechat.yaml
3. ~/nginx-ourchat.conf
4. ~/our-chat.pem
5. ~/our-chat.pw

Chat history is intentionally temporary (180-day retention).

## Development Mode

The install script creates a systemd user service for backend development:
```bash
systemctl --user status librechat-backend.service
systemctl --user restart librechat-backend.service
```

Custom deploy-compose file should remove `api:` and `client:` services when using this mode.

## Troubleshooting

### Docker group issues
If docker group doesn't exist (centralized IAM):
```bash
# Option 1: Manual /etc/group edit
docker:x:986:ochat

# Option 2: Use alternate group (ldocker)
echo -e '{\n  "group": "ldocker"\n}' | sudo tee /etc/docker/daemon.json
systemctl edit docker.socket  # Set SocketGroup=ldocker
systemctl restart docker.socket
```

### Moving Docker data directory
```bash
NEWROOT="/vol1/var/lib/docker"
sudo systemctl stop docker
echo -e "{\n \"data-root\": \"${NEWROOT}\"\n}" | sudo tee /etc/docker/daemon.json
sudo rsync -aAHSXv --mkpath /var/lib/docker/ ${NEWROOT}/
sudo mv /var/lib/docker /var/lib/docker.old
sudo systemctl start docker
```

### Debug logging
Enable in ~/.env, copy to ~/LibreChat/.env, restart without -d to see console output.

## System Design Notes

### Budget Control Limitations
LibreChat lacks per-user cost controls. AWS Budgets only alerts, doesn't enforce limits. Proposed solution: Daily accumulated budget allowing burst usage while preventing monthly overruns. See: https://github.com/dirkpetersen/our-chat/issues/1

### API Access
LibreChat doesn't support direct API access (RAG API requires web UI). API users should access Bedrock directly with separate AWS accounts. Use bedrock-test.py as reference implementation.

### On-Premises Integration
Connect to HPC clusters or local GPUs via custom endpoints in librechat.yaml. Example: Llama-CPP endpoints commented out in config.

## Security Considerations

- No per-user cost tracking - all usage appears as single AWS account line item
- SSL required (no plain HTTP operation)
- Security headers in NGINX: HSTS, X-Content-Type-Options, Cache-Control
- Encrypted volumes recommended for sensitive deployments
- LDAP credentials stored in plaintext in ~/.env (chmod 600)
- AWS credentials stored in ~/.aws/ and ~/.env
- Token generation required for CREDS_KEY, JWT_SECRET, etc. — `.env.ochat` values are placeholders

## Missing LibreChat Features

Tracked upstream issues:
- Mature LDAP authorization (groups): https://github.com/danny-avila/LibreChat/issues/3955
- Track which LLM provided answer: https://github.com/danny-avila/LibreChat/issues/4012
- Better retention handling: https://github.com/danny-avila/LibreChat/issues/2365

## Prerequisites Summary

**Required**:
- Linux VM: 1GB RAM, 25GB disk, Amazon Linux/RHEL/Ubuntu
- DNS FQDN pointing to server
- Ports 80, 443 accessible
- AWS Bedrock service account with AmazonBedrockFullAccess
- SSL certificate (from IT or Let's Encrypt)

**Optional**:
- LDAP server access on port 636
- LDAP security group for user authorization
- Pre-installed security software
- Encrypted volume
