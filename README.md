# Drasi Apps Infrastructure - PoT (Proof of Technology)

Azure infrastructure for Drasi on Azure Container Apps.

## State and replica readiness

Current state behavior and replica constraints are documented in `docs/drasi-state-contract.md`.

- Current runtime mode is single replica (`minReplicas: 1`, `maxReplicas: 1`).
- Durable runtime config and `redb` state are persisted on Azure Files at `/drasi-persist`.
- Multi-replica promotion requires passing the explicit readiness gates for partition ownership, replay determinism, and conflict handling.

Before changing replica counts, review and complete the checklist in `docs/drasi-state-contract.md`.

## How IaC creates durable file-share state

The durable state path is created entirely through Bicep in `azure/modules/drasi-runtime.bicep` and wired from `azure/prod/main-prod.bicep`.

### What the IaC provisions

- A Storage Account for runtime persistence (`Microsoft.Storage/storageAccounts`).
- A File Share for Drasi runtime data (`Microsoft.Storage/storageAccounts/fileServices/shares`).
- A managed-environment storage binding in Container Apps (`Microsoft.App/managedEnvironments/storages`) that points to the Azure File Share.
- A Container App volume using `storageType: 'AzureFile'`, mounted at `/drasi-persist`.

### How runtime config and state are persisted

- The runtime config secret (`server.yaml`) is mounted separately as a secret volume at `/config-secret`.
- Startup logic creates `/drasi-persist` and copies `server.yaml` only when `/drasi-persist/server.yaml` does not already exist.
- Drasi then starts with `--config /drasi-persist/server.yaml`, so API-created mutations persist on the file share.
- `STATE_STORE_PATH` is set to `/drasi-persist/state.redb`, and runtime config defaults to `stateStore.kind: redb`.

### Why this matters

- Restarting a container or rolling revisions no longer wipes runtime config and `redb` state.
- The repository keeps single-replica defaults while multi-replica readiness gates are validated.

## Azure Developer CLI workflow

This repository is configured for Azure Developer CLI (`azd`) deployment.

### 1. Create or select an azd environment

```powershell
azd env new <env-name>
azd env select <env-name>
```

### 2. Set required environment values

```powershell
azd env set WORKLOADPREFIX drasi
azd env set ENVIRONMENT prod
azd env set CONTAINERIMAGE ghcr.io/drasi-project/drasi-server@sha256:c3b025b35626a9877631197391fbc527f4aff65c88516214a427462942b451ba
azd env set ACAINFRASTRUCTURESUBNETRESOURCEID /subscriptions/<subscription-id>/resourceGroups/<network-rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<aca-subnet>
azd env set RUNTIMECONFIGSECRETURI https://<kv-name>.vault.azure.net/secrets/drasi-runtime-config/<secret-version>
azd env set POSTGRESHOST <postgres-server>.postgres.database.azure.com
azd env set POSTGRESDATABASENAME drasi
azd env set POSTGRESUSERNAME drasi_admin
azd env set POSTGRESPASSWORDSECRETURI https://<kv-name>.vault.azure.net/secrets/drasi-postgres-password/<secret-version>
azd env set REDISHOST <redis-host>.redis.cache.windows.net
azd env set REDISPASSWORDSECRETURI https://<kv-name>.vault.azure.net/secrets/drasi-redis-password/<secret-version>
azd env set KEYVAULTNAME <kv-name>
```

### 3. Validate and deploy

```powershell
# Preview only
./scripts/validate.ps1 -EnvironmentName <env-name>

# Apply infrastructure + deploy phase
./scripts/deploy-azd.ps1 -EnvironmentName <env-name>
```

`azure.yaml` hooks run automatically:

- `scripts/azd-preprovision.ps1` before provision (`az bicep build`)
- `scripts/azd-postprovision.ps1` after provision (Container App state + `/health` checks)
