# AI Week OurChat Deployment Plan

## 1. Purpose and Scope

This document defines requirements and responsibilities for a temporary OurChat (LibreChat) deployment supporting AI Week — a multi-session public-facing event with open exhibit access, live sessions, and pre-registered participants. The deployment must be accessible from attendees' personal cell phones without VPN.

OurChat is a configuration and deployment wrapper around [LibreChat](https://github.com/danny-avila/LibreChat). This document covers requirements, the revised LLM provider strategy, the split-responsibility operating model, and a summary of all configuration changes made in this repo relative to upstream LibreChat.

---

## 2. Stakeholders and Responsibilities

Three teams share responsibility. Boundaries are intentional — the ochat application account is the sole interface between infrastructure and the application layer.

### Infrastructure Team
- OS provisioning, patching, and reboots
- Firewall rules and network routing
- SSL certificate provisioning
- Cloud account management (Azure subscription, Azure AI Foundry deployments)
- Active Directory — creating and managing the `ai-week-access` security group and any child groups

### OurChat Application Team (ochat user)
Operates entirely under the `ochat` service account. Responsibilities:
- LibreChat installation, updates, and configuration (`~/our-chat/`, `~/LibreChat/`)
- Managing `.env`, `librechat.yaml`, `nginx-ourchat.conf`
- Docker Compose lifecycle (`~/bin/update-librechat.sh`)
- Model endpoint configuration (Azure AI Foundry keys, HuangComplex endpoint)
- RAG and data retention configuration

The application team may `sudo su - ochat`, install OS packages required by the application, and request reboots. All other OS-level changes remain with the infrastructure team.

### Service Desk
- Owns the authorization process for Tiers 2 and 3 (see Section 4)
- Adds attendees to AD groups in real time during sessions and at the exhibit desk
- Does not manage infrastructure or application configuration

---

## 3. LLM Provider Strategy

### Original Plan
The initial architecture proposed routing users to multiple independent cloud providers:
- **AWS Bedrock** — Anthropic Claude models
- **Azure AI Foundry** — OpenAI models
- **Google Vertex AI** — Gemini models
- **HuangComplex** (local Nvidia DGX) — open-source models

### Revised Plan
To simplify credential management, reduce firewall exposure, and present a unified enterprise contract surface, all cloud-hosted LLMs are consolidated into **Azure AI Foundry**. This covers:

- **Anthropic** — Claude Opus 4.6, Claude Sonnet 4.6, Claude Haiku 4.5
- **OpenAI** — GPT-5.3 (or current flagship at deployment time)
- **Google** — TBD (Gemini availability in Azure AI Foundry to be confirmed)

**HuangComplex** (local Nvidia DGX) remains as the on-premises provider for locally-hosted open-source models, demonstrating the hybrid cloud + on-prem capability that is a key goal of the event.

### Why This Matters for the Demo
The consolidated strategy directly supports the AI Week demonstration goal: showing attendees that a single interface can access the leading commercial models from all major AI providers, plus a local on-premises alternative — without requiring separate accounts or interfaces for each.

---

## 4. Authentication and Authorization

### Authentication — Duo OIDC
Replace LDAP with Duo SSO as an OpenID Connect (OIDC) provider. LibreChat's built-in OIDC support handles this without code changes. Duo issues Duo Push to the user's phone as the MFA step, satisfying the mobile-first access requirement.

**Infrastructure team delivers**: Duo SSO generic OIDC application with redirect URI `https://<fqdn>/oauth/openid/callback`, client ID, client secret, issuer URL, and groups claim configured.

### Authorization — Three Access Tiers

All tiers resolve to a single AD security group `ai-week-access`. LibreChat enforces group membership at login via the OIDC groups claim.

| Tier | Population | Registration path | Managed by |
|------|-----------|-------------------|------------|
| 1 | AI Week pre-registrants | Batch import from event signup list before event | IT |
| 2 | Session attendees | Added to `ai-week-access` at session check-in | Service desk |
| 3 | Exhibit walk-bys | Added to `ai-week-access` at the exhibit desk | Service desk |

**Service desk tooling requirement**: The service desk attendant needs a fast method to add a user by name or username to `ai-week-access` in real time. Options: AD self-service portal, a delegated PowerShell session, or a simple web form backed by an AD write operation. This tooling is an infrastructure team deliverable.

**Group propagation latency**: AD → Duo sync typically takes 1–5 minutes. Users added mid-session may need to wait briefly before their login succeeds.

---

## 5. Network and Access Requirements

- Public FQDN with valid SSL certificate (Let's Encrypt or enterprise cert)
- Inbound TCP 443 open to all (or to campus network ranges if event is on-campus)
- Outbound HTTPS from the server to Duo SSO endpoints and Azure AI Foundry endpoints
- Outbound TCP from the server to HuangComplex API port on the local network
- No VPN required for end users — direct HTTPS from personal devices

---

## 6. RAG Configuration

The RAG (Retrieval Augmented Generation) pipeline has been optimized in this deployment relative to LibreChat defaults:

| Parameter | LibreChat default | OurChat setting | Rationale |
|-----------|------------------|-----------------|-----------|
| `EMBEDDINGS_PROVIDER` | openai | `bedrock` | Uses AWS Bedrock for embeddings, no OpenAI dependency |
| `EMBEDDINGS_MODEL` | text-embedding-3-small | `amazon.titan-embed-text-v2:0` | Current-generation Titan embedding model |
| `CHUNK_SIZE` | 1500 | `5000` | Larger chunks preserve more context per retrieval hit |
| `RAG_USE_FULL_CONTEXT` | false | `true` | Passes full retrieved chunks rather than summaries |
| `PDF_EXTRACT_IMAGES` | false | `false` | Kept off; image extraction is resource-intensive |

**Note for AI Week**: If Azure AI Foundry is the sole LLM provider, consider also switching `EMBEDDINGS_PROVIDER` to an Azure-hosted embedding model to eliminate the AWS Bedrock dependency entirely.

---

## 7. OurChat Configuration Changes vs Base LibreChat

This section documents every substantive change made in OurChat relative to a fresh LibreChat installation. This is the authoritative delta for anyone comparing the two.

### `librechat.yaml`

| Change | LibreChat default | OurChat value |
|--------|------------------|---------------|
| Schema version | varies | `1.3.4` |
| Terms of service modal | disabled | Enabled — custom university acceptable use policy, mandatory acceptance before first use |
| Privacy policy link | none | Set to `university.edu/acceptable-use` |
| Registration `allowedDomains` | none | `university.edu` (restricts self-registration to university email addresses) |
| Registration `socialLogins` | all enabled | `[]` — disabled; authentication is LDAP or OIDC only |
| Bedrock `streamRate` | default | `75` — throttle to reduce token rate pressure |
| Bedrock `titleModel` | none | `us.anthropic.claude-haiku-4-5-20251001-v1:0` — uses inference profile prefix |
| File upload limit (default endpoint) | LibreChat default | 10 files, 50 MB total |
| File upload limit (Bedrock) | LibreChat default | 25 files, 50 MB total |
| Custom on-prem endpoints | none | Commented examples for Llama-CPP A40 and A100 (HuangComplex pattern) |

### `.env` / `.env.ochat`

| Parameter | LibreChat default | OurChat value | Rationale |
|-----------|------------------|---------------|-----------|
| `ENDPOINTS` | openAI | `bedrock,google` | Scoped to active providers only |
| `BEDROCK_AWS_MODELS` | all known models | Curated list of 6 current-generation models with `global.`/`us.` inference profile prefixes | Prevents obsolete or unsupported models from appearing |
| `GOOGLE_MODELS` | example list | Current Gemini 3.x and 2.5 model IDs | Updated to current generation |
| `GEMINI_IMAGE_MODEL` | not set | `gemini-3-pro-image-preview,gemini-2.5-flash-image` | Enables image generation via Gemini |
| `GOOGLE_TITLE_MODEL` | gemini-pro | `gemini-2.5-flash-lite` | Faster/cheaper model for conversation title generation |
| `EMBEDDINGS_PROVIDER` | openai | `bedrock` | No OpenAI dependency |
| `EMBEDDINGS_MODEL` | text-embedding-3-small | `amazon.titan-embed-text-v2:0` | Current-generation Bedrock embedding model |
| `CHUNK_SIZE` | 1500 | `5000` | Larger RAG context chunks |
| `RAG_USE_FULL_CONTEXT` | false | `true` | Full chunk context passed to model |
| `DEBUG_PLUGINS` | true | `false` | Reduce log noise in production |
| `DISABLE_COMPRESSION` | false (Express compresses) | `true` | NGINX handles compression; avoid double-compression |
| `APP_TITLE` | "My LibreChat" | `"University Chat"` | Deployment branding |
| `BEDROCK_AWS_SESSION_TOKEN` | not present | Commented stub | Enables IAM role / temporary credential support |
| `LDAP_STARTTLS` | not present | Commented stub | Available for enabling TLS upgrade on LDAP connections |
| `GOOGLE_CLOUD_PROJECT` | not present | Commented stub in Google section | Required for Vertex AI (if switching from AI Studio) |
| `ALLOW_SOCIAL_LOGIN` | false | `false` | Kept off; OIDC is configured separately via `OPENID_*` |
| `ALLOW_PASSWORD_RESET` | true | `false` | LDAP/OIDC deployments have no local passwords to reset |
| BingAI section | present | Removed | BingAI removed from LibreChat |

### `nginx-ourchat.conf`
Custom NGINX configuration replacing LibreChat's default. Key additions:
- TLS 1.2/1.3 only, Mozilla intermediate cipher suite
- HSTS, `X-Content-Type-Options`, `Cache-Control` security headers
- HTTP → HTTPS redirect on port 80
- Client max body size 25 MB (for file uploads)
- SSL certificate from enterprise PKCS12 or Let's Encrypt (two commented options)

### `deploy-compose-ourchat.yml` (generated at install time, not in repo)
Derived from LibreChat's `deploy-compose.yml` by `install-librechat.sh` via `sed`:
- MongoDB external port exposed as `27018` (for maintenance access)
- SSL certificate volume mounted into NGINX container
- NGINX config replaced with `nginx-ourchat.conf`

### `tests/bedrock-test.py`
- Writes AWS credentials to `[bedrock]` profile (not `[default]`)
- Uses `boto3.Session(profile_name='bedrock')`
- Auto-retries model invocation with `us.{model_id}` inference profile prefix if the direct call returns a `ValidationException` about inference profiles

### `purge_old_messages.py`
- Connects to MongoDB on port `27018` (external host port)
- Deletes messages and files older than 180 days
- Runs daily at 2:22 AM via cron

---

## 8. Open Items

| Item | Owner | Notes |
|------|-------|-------|
| Azure AI Foundry subscription and model deployments | Infrastructure | Anthropic, OpenAI, and Google (TBD) models need to be deployed; API key and base URL required |
| Google/Gemini availability in Azure AI Foundry | Infrastructure | Confirm whether Gemini is available or if a direct Vertex AI connection is needed |
| HuangComplex API endpoint and models | Application team | Confirm vLLM/Ollama URL, port, auth method, and which models are available for the event |
| Duo SSO OIDC application | Infrastructure | Client ID, secret, issuer URL, and groups claim format required before `.env` can be completed |
| `ai-week-access` AD group | Infrastructure | Create group; confirm Duo sync and groups claim format in ID token |
| Service desk tooling for real-time group adds | Infrastructure | Portal, PowerShell delegation, or web form for Tiers 2 and 3 |
| Session and token expiry tuning | Application team | Default 15-min session / 7-day refresh — review for event context |
| Post-event data purge | Application team | Run `purge_old_messages.py` manually or shorten retention window after event |
