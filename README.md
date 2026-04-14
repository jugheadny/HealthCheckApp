# jria-healthcheck-stub

Node.js healthcheck stub. Deployed to Azure App Service (Linux, Node 20 LTS) via
`WEBSITE_RUN_FROM_PACKAGE` pointing at a SAS-signed blob URL.

Purpose: stand up the App Service plan + networking ahead of the real
application code being deployed, so infra work is unblocked.

## Endpoints

- `GET /health`, `/healthz`, `/readiness` → `{status, uptime, timestamp, checks}`
- `POST /set-ready`, `/set-not-ready` → toggle readiness flag (testing)
- `POST /set-alive`, `/set-not-alive` → toggle liveness flag (testing)

## Azure deployment

Infra lives in the Cubicle13 homelab IaC repo:
`InfrastructureAsCode/terraform/projects/smbc-jria-healthcheck/`

- Resource Group: `rg-smbc-jria-healthcheck-poc`
- App Service Plan: `asp-smbc-jria-healthcheck-poc` (Linux, B1)
- Web App: `app-smbc-jria-healthcheck-poc.azurewebsites.net`
- Zip host: `cubicle13backup/jria-healthcheck-stub/app.zip` (1-year SAS)

## Deploy

```bash
az login   # once per day
./scripts/deploy.sh
```

Runs `npm run package` → `az storage blob upload --overwrite` → `az webapp restart`
→ probes `/health`.
