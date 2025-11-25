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
curl https://raw.githubusercontent.com/dirkpetersen/our-chat/refs/heads/main/prepare-server.sh | bash

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

# Update LibreChat
cd ~/LibreChat
docker compose -f deploy-compose-ourchat.yml down
git pull
docker compose -f deploy-compose-ourchat.yml pull
docker compose -f deploy-compose-ourchat.yml up -d

# Enable debug logging
vi ~/.env  # Set DEBUG_LOGGING=true
cp ~/.env ~/LibreChat/
docker compose -f ~/LibreChat/deploy-compose-ourchat.yml down
docker compose -f ~/LibreChat/deploy-compose-ourchat.yml up  # without -d to see logs

# Manual purge of old messages
~/our-chat/purge_old_messages.py
```

## Key Configuration Files

### .env.ochat (template copied to ~/.env)
- Primary configuration copied to ~/LibreChat/.env during installation
- AWS Bedrock credentials: `BEDROCK_AWS_ACCESS_KEY_ID`, `BEDROCK_AWS_SECRET_ACCESS_KEY`, `BEDROCK_AWS_DEFAULT_REGION`
- LDAP settings: `LDAP_URL`, `LDAP_BIND_DN`, `LDAP_SEARCH_FILTER`, etc.
- Security tokens: `CREDS_KEY`, `CREDS_IV`, `JWT_SECRET`, `JWT_REFRESH_SECRET`, `MEILI_MASTER_KEY`
- Generate tokens at: https://www.librechat.ai/toolkit/creds_generator
- install-librechat.sh expands environment variables when copying to LibreChat

### librechat.yaml
- LibreChat-specific configuration (version 1.1.7)
- Terms of service modal with usage policy
- Registration restrictions (allowedDomains: oregonstate.edu)
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
3. Copies config files from ~/ to ~/LibreChat/
4. Activates SSL certificates (Certbot or custom)
5. Sets up cron jobs:
   - `@reboot` - auto-start LibreChat
   - `22 2 * * *` - daily purge of old messages
6. Creates systemd user service for dev mode (librechat-backend.service)
7. Installs AWS CLI v2 if not present

**Key behavior**: Environment variables in ~/.env are expanded when copied to ~/LibreChat/.env

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
- Writes AWS credentials to ~/.aws/credentials and ~/.aws/config
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

## File Structure

```
our-chat/
├── .env.ochat              # Template for main configuration
├── librechat.yaml          # LibreChat YAML config template
├── nginx-ourchat.conf      # NGINX SSL reverse proxy config
├── install-librechat.sh    # Main installation script
├── prepare-server.sh       # Server preparation (root)
├── purge_old_messages.py   # Data retention utility
├── moin.py                 # Punderdome 3000 pun battle game (easter egg)
├── tests/
│   ├── bedrock-test.py    # AWS Bedrock connectivity test
│   └── ldap-test.py       # LDAP configuration validator
└── README.md              # Comprehensive documentation

After installation creates:
~/LibreChat/               # Cloned from github.com/danny-avila/LibreChat
├── .env                   # Expanded from ~/.env
├── librechat.yaml         # Copied from ~/
├── client/nginx-ourchat.conf
├── client/ssl/            # SSL certificates mounted here
│   ├── our-chat.pem
│   └── our-chat.pw
└── deploy-compose-ourchat.yml  # Modified from deploy-compose.yml
```

## Authentication & Authorization

### LDAP/AD Integration (Phase 1 - JIT Provisioning)
- Just-In-Time user creation on first login
- LDAP_SEARCH_FILTER restricts access to security group members
  - Example: `(&(sAMAccountName={{username}})(memberOf=CN=our-chat-users,...))`
  - Returns 401 (AuthN) instead of 403 (AuthZ) for non-members - this is a known limitation
- LDAP_LOGIN_USES_USERNAME=true allows login with username instead of full email
- Test with: `~/our-chat/tests/ldap-test.py <username>`

### Email Domain Restriction (Alternative)
If not using LDAP, set in librechat.yaml:
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
- Configure available models in .env.ochat BEDROCK_AWS_MODELS
- Unsupported models:
  - No streaming: ai21.j2-mid-v1
  - No conversation history: ai21.j2-ultra-v1, cohere.command-text-v14

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
- Consider pre-installing security software: SIEM forwarders, antivirus, IPS
- LDAP credentials stored in plaintext in ~/.env (chmod 600)
- AWS credentials stored in ~/.aws/ and ~/.env
- Token generation required for CREDS_KEY, JWT_SECRET, etc.

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
