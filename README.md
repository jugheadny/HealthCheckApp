# jria-healthcheck-stub

Node.js healthcheck stub. Deployed to **Azure App Service** (Linux, Node 20 LTS,
S1 plan in northcentralus) via `WEBSITE_RUN_FROM_PACKAGE` pointing at a
SAS-signed `app.zip` blob in `cubicle13backup`. Stand-in for real SMBC JRIA
application code so infra/networking work isn't blocked.

## Endpoints

- `GET /health`, `/healthz`, `/readiness` → `{status, uptime, timestamp, checks}`
- `POST /set-ready`, `/set-not-ready` → toggle readiness flag (testing)
- `POST /set-alive`, `/set-not-alive` → toggle liveness flag (testing)

## Azure deployment

Infra lives in the Cubicle13 IaC repo:
`InfrastructureAsCode/terraform/projects/smbc-jria-healthcheck/`

| Resource | Name |
|---|---|
| Resource Group | `rg-smbc-jria-healthcheck-poc` (northcentralus) |
| App Service Plan | `asp-smbc-jria-healthcheck-poc` (Linux S1) |
| Web App | `app-smbc-jria-healthcheck-poc.azurewebsites.net` |
| Zip blob | `cubicle13backup` / `jria-healthcheck-stub` / `app.zip` (SAS, 1-year TTL) |

> **Note on region:** This Avanade EA subscription has every Microsoft.Web SKU
> quota set to 0 in eastus / eastus2 / westus2 / southcentralus / westeurope /
> northeurope. northcentralus has open quota for Basic and Standard VMs. The
> blob storage account stays in eastus — App Service pulls the zip on warmup
> only, cross-region latency is negligible.

## Deploy

```bash
az login   # once per day
./scripts/deploy.sh                 # full build + upload + restart + probe
SKIP_BUILD=1 ./scripts/deploy.sh    # upload existing app.zip without rebuilding
```

`deploy.sh` runs: `npm run package` → `az storage blob upload --overwrite` →
`az webapp restart` → probe `/health`.

## Container alternative

A `Dockerfile` is also present (used during the Container Apps POC pivot). The
authoritative deploy target for this POC is App Service via zip — the
Dockerfile is kept for local container testing and a possible Container
Apps fallback if quotas change.
