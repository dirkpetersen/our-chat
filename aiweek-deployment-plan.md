# AI Week OurChat Deployment Plan

## Overview

Temporary LibreChat deployment for AI Week — an event with three overlapping access tiers, Duo OAuth authentication, models hosted in Azure AI Foundry and on the local HuangComplex DGX cluster, and firewall access for attendees on personal devices.

**Base stack**: OurChat (this repo) on an AWS EC2 or on-prem Linux VM, Docker Compose, NGINX SSL termination.

---

## Access Tiers

Three populations with different registration workflows, all converging on a single AD security group `ai-week-access`:

| Tier | Population | Registration method | Who manages |
|------|-----------|---------------------|-------------|
| 1 | AI Week pre-registrants | Batch-added before event via AD group import from signup list | IT |
| 2 | Session attendees | Service desk adds individuals to `ai-week-access` during session | Service desk |
| 3 | Walk-by exhibit visitors | Service desk adds individuals on the spot at the desk | Service desk |

**Why a single group**: LibreChat's OIDC integration supports one required-role check (`OPENID_REQUIRED_ROLE`). Using a single `ai-week-access` group keeps the Duo/AD side simple — everyone authorized is in one place, sub-tracking by tier can be done via AD description fields or a separate spreadsheet.

### Service Desk Operations (Tiers 2 & 3)

The service desk attendant needs a fast path to add users mid-session. Options in order of preference:

1. **AD group self-service portal** (if available at your institution) — attendant looks up user by name, adds to `ai-week-access`
2. **PowerShell one-liner** on a pre-configured laptop:
   ```powershell
   Add-ADGroupMember -Identity "ai-week-access" -Members (Get-ADUser -Filter {SamAccountName -eq "<username>"})
   ```
3. **LibreChat admin role** — grant the service desk account the LibreChat admin role, use the built-in user management UI to invite by email after they first authenticate with Duo

For walk-bys (Tier 3) who may not have Duo enrolled, a fallback option is a shared temporary guest account pre-loaded on a device at the exhibit desk (tradeoff: no per-user audit trail).

---

## Authentication: Duo OIDC

Replace LDAP with Duo SSO acting as an OIDC provider. LibreChat's `OPENID_*` variables handle this natively.

### Duo SSO Setup (IT side)

1. In the Duo Admin Panel, create a new **Generic OIDC application**
2. Set the redirect URI: `https://<fqdn>/oauth/openid/callback`
3. Configure groups claim to include AD group membership in the ID token
4. Note the **Client ID**, **Client Secret**, and **Issuer URL** (typically `https://<your-duo-sso-host>/oauth/v1`)
5. Create AD security group `ai-week-access` and configure Duo to sync it

### `.env` changes

```bash
# Disable local registration and LDAP
ALLOW_REGISTRATION=false
ALLOW_EMAIL_LOGIN=false
ALLOW_SOCIAL_LOGIN=true
ALLOW_SOCIAL_REGISTRATION=true

# Duo OIDC
OPENID_CLIENT_ID=<duo-client-id>
OPENID_CLIENT_SECRET=<duo-client-secret>
OPENID_ISSUER=https://<duo-sso-host>/oauth/v1/.well-known/openid-configuration
OPENID_SESSION_SECRET=<random-32-char-string>
OPENID_SCOPE="openid profile email groups"
OPENID_CALLBACK_URL=/oauth/openid/callback
OPENID_BUTTON_LABEL="Sign in with University SSO (Duo)"
OPENID_REQUIRED_ROLE=ai-week-access
OPENID_REQUIRED_ROLE_TOKEN_KIND=id_token
OPENID_REQUIRED_ROLE_PARAMETER_PATH=groups
```

**Note**: `OPENID_REQUIRED_ROLE_PARAMETER_PATH=groups` assumes Duo puts group names in a `groups` claim in the ID token. Verify with `OPENID_REQUIRED_ROLE_TOKEN_KIND=access_token` if the groups are in the access token instead. Test by decoding the token at jwt.io.

### `librechat.yaml` changes

```yaml
registration:
  socialLogins: ['openid']   # Duo is the only login path
  allowedDomains: []          # Domain restriction no longer needed; Duo group controls access
```

---

## Network / Firewall

Attendees access from personal cell phones — no VPN.

### Requirements

- **Inbound**: TCP 443 open to `0.0.0.0/0` (or scoped to campus IP ranges if on campus network)
- **Inbound**: TCP 80 open for Let's Encrypt ACME challenge (or pre-install cert and leave 80 closed)
- **Outbound**: HTTPS to `*.duosecurity.com` and `*.duo.com` for Duo OIDC token exchange
- **Outbound**: HTTPS to Azure AI Foundry endpoints (see model section below)
- **Outbound**: TCP to HuangComplex API port (see model section below)
- **DNS**: Public FQDN resolving to the server's IP

### SSL

Use Let's Encrypt if the server has a public IP, otherwise install an enterprise cert per the base OurChat instructions. Let's Encrypt is simpler for a temporary event deployment:

```bash
sudo certbot certonly --standalone -d <fqdn>
```

---

## Model Endpoints

### Azure AI Foundry

Azure AI Foundry exposes an OpenAI-compatible API. Each model family below gets its own deployment in the Azure portal.

**Deployments to create in Azure AI Foundry:**

| Model | Azure deployment name (suggested) |
|-------|----------------------------------|
| Claude Opus 4.6 | `claude-opus-4-6` |
| Claude Sonnet 4.6 | `claude-sonnet-4-6` |
| Claude Haiku 4.5 | `claude-haiku-4-5` |
| GPT-5.3 | `gpt-5-3` |
| Grok | `grok` |

**`librechat.yaml` custom endpoint block:**

```yaml
endpoints:
  custom:
    - name: "Azure AI Foundry"
      apiKey: "${AZURE_FOUNDRY_API_KEY}"
      baseURL: "https://<resource>.services.ai.azure.com/models"
      models:
        default: ["claude-opus-4-6", "claude-sonnet-4-6", "claude-haiku-4-5", "gpt-5-3", "grok"]
        fetch: false
      titleConvo: true
      titleModel: "claude-haiku-4-5"
      modelDisplayLabel: "Azure AI Foundry"
```

**`.env` addition:**

```bash
AZURE_FOUNDRY_API_KEY=<azure-ai-foundry-api-key>
```

**Note**: If Azure AI Foundry Claude models require Anthropic-format requests rather than OpenAI format, a separate custom endpoint block per model family may be needed. Verify in Azure AI Foundry's model card whether the deployment uses the OpenAI-compatible or Messages API.

### HuangComplex (Local DGX)

Assumes vLLM or Ollama is running on the DGX and exposing an OpenAI-compatible API. The service endpoint must be reachable from the OurChat server (either direct network path or SSH tunnel).

**`librechat.yaml` custom endpoint block:**

```yaml
    - name: "HuangComplex"
      apiKey: "${HUANGCOMPLEX_API_KEY}"
      baseURL: "http://<huangcomplex-host>:<port>/v1"
      models:
        default: []
        fetch: true          # fetch model list dynamically from vLLM
      titleConvo: true
      titleModel: "auto"
      modelDisplayLabel: "HuangComplex (On-Prem)"
```

**`.env` addition:**

```bash
HUANGCOMPLEX_API_KEY=<api-key-or-none>
```

If vLLM is running without authentication, set `HUANGCOMPLEX_API_KEY=none`.

---

## Complete `.env` Delta from Base OurChat

Changes relative to `.env.ochat` for this deployment:

```bash
# Endpoints — add azure and huangcomplex custom endpoints
ENDPOINTS=custom,google

# Auth — switch from LDAP to Duo OIDC
ALLOW_REGISTRATION=false
ALLOW_EMAIL_LOGIN=false
ALLOW_SOCIAL_LOGIN=true
ALLOW_SOCIAL_REGISTRATION=true

# Remove or comment out all LDAP_* variables

# Duo OIDC (fill in from Duo Admin Panel)
OPENID_CLIENT_ID=
OPENID_CLIENT_SECRET=
OPENID_ISSUER=
OPENID_SESSION_SECRET=
OPENID_SCOPE="openid profile email groups"
OPENID_CALLBACK_URL=/oauth/openid/callback
OPENID_BUTTON_LABEL="Sign in with University SSO (Duo)"
OPENID_REQUIRED_ROLE=ai-week-access
OPENID_REQUIRED_ROLE_TOKEN_KIND=id_token
OPENID_REQUIRED_ROLE_PARAMETER_PATH=groups

# Azure AI Foundry
AZURE_FOUNDRY_API_KEY=

# HuangComplex
HUANGCOMPLEX_API_KEY=

# Event branding
APP_TITLE="AI Week Chat"
CUSTOM_FOOTER="AI Week 2025 — Powered by Azure AI Foundry and HuangComplex"
```

---

## Deployment Steps

1. **Pre-event (IT, 1 week before)**
   - Create `ai-week-access` AD group
   - Import AI Week pre-registrants (Tier 1) into the group from signup list export
   - Configure Duo SSO generic OIDC application, note credentials
   - Deploy model endpoints in Azure AI Foundry, note API key and base URL
   - Confirm HuangComplex vLLM API is reachable from the deployment server

2. **Server setup (IT, 2 days before)**
   - Run `prepare-server.sh` to create `ochat` user and install Docker
   - Clone `our-chat`, copy config templates
   - Fill in `.env` with Duo OIDC credentials, Azure Foundry key, HuangComplex URL
   - Update `librechat.yaml` with Azure Foundry and HuangComplex endpoint blocks, set `socialLogins: ['openid']`
   - Install SSL cert (Let's Encrypt or enterprise)
   - Open firewall: inbound 443, outbound to Duo and Azure
   - Run `install-librechat.sh`
   - Test login with a Tier 1 account, verify model access

3. **Event day**
   - Service desk attendant has AD group management access ready (portal or PowerShell)
   - For Tier 2 (sessions): add attendees to `ai-week-access` as they arrive; changes propagate to Duo within ~1–5 minutes
   - For Tier 3 (walk-bys): same process; consider a short URL or QR code pointing to the chat URL posted at the desk

4. **Post-event teardown**
   - `docker compose -f ~/LibreChat/deploy-compose-ourchat.yml down`
   - Archive or purge `ai-week-access` AD group
   - Revoke Azure AI Foundry API key

---

## Open Questions / Decisions Needed

| Question | Options |
|----------|---------|
| Duo groups claim format | Confirm whether `groups` claim contains group names or SIDs; adjust `OPENID_REQUIRED_ROLE_PARAMETER_PATH` accordingly |
| Azure Foundry Claude API format | OpenAI-compatible vs. Anthropic Messages API — affects whether one custom endpoint or two are needed |
| HuangComplex models | Which models are deployed and available on the DGX for the event? |
| Walk-by guest access | Per-user Duo enrollment required, or shared kiosk device? |
| Session token lifetime | Default is 15 min session / 7 day refresh — adjust `SESSION_EXPIRY` and `REFRESH_TOKEN_EXPIRY` for event context |
| Data retention | Default 180-day purge in `purge_old_messages.py` — shorten to 30 days post-event or run a manual purge after teardown |
