# jria-healthcheck-stub

Node.js healthcheck stub. Deployed to **Azure Container Apps** as an immutable
container image built by ACR Tasks (server-side `az acr build` — no local Docker
needed). Stand-in for real JRIA application code so infra/networking work isn't
blocked.

## Endpoints

- `GET /health`, `/healthz`, `/readiness` → `{status, uptime, timestamp, checks}`
- `POST /set-ready`, `/set-not-ready` → toggle readiness flag (testing)
- `POST /set-alive`, `/set-not-alive` → toggle liveness flag (testing)

## Azure deployment

Infra lives in the Cubicle13 IaC repo:
`InfrastructureAsCode/terraform/projects/smbc-jria-healthcheck/`

| Resource | Name |
|---|---|
| Resource Group | `rg-smbc-jria-healthcheck-poc` |
| ACR | `acrsmbcjriahcpoc` (Basic, AAD-only) |
| Container App Environment | `cae-smbc-jria-healthcheck-poc` |
| Container App | `ca-smbc-jria-healthcheck-poc` |

The Container App pulls images via system-assigned managed identity (`AcrPull`
role on the ACR) — no registry passwords stored anywhere.

> **Why Container Apps not App Service?** This Avanade EA subscription has every
> `Microsoft.Web` SKU quota (Free / Basic / Standard / Premium v2 / Premium v3 /
> Premium0V3) set to 0. Container Apps live under `Microsoft.App` — different
> quota pool, no block.

## Deploy

```bash
az login   # once per day
./scripts/deploy.sh                 # tag = git short-sha
TAG=v1 ./scripts/deploy.sh          # explicit tag
```

The script `az acr build`s the image inside ACR (no Docker daemon required),
then `az containerapp update --image …` rolls a new revision (Single revision
mode → 100% traffic shift), then probes `/health`.
