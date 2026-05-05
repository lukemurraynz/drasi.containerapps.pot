# Validation runbook

## Preconditions

- `azure.yaml` exists and points infra to `azure/prod`.
- `azd` environment is configured with required variables (`WORKLOADPREFIX` or `WORKLOAD_PREFIX`, `ENVIRONMENT`, `CONTAINERIMAGE`, `ACAINFRASTRUCTURESUBNETRESOURCEID`, `RUNTIMECONFIGSECRETURI`, `POSTGRESHOST`, `POSTGRESDATABASENAME`, `POSTGRESUSERNAME`, `POSTGRESPASSWORDSECRETURI`, `REDISHOST`, `REDISPASSWORDSECRETURI`, `KEYVAULTNAME`).
- Baseline query results are captured.
- Monitoring and alerting are enabled.

## 1. Template validation (azd preprovision hook)

```bash
az bicep build --file azure/prod/main.bicep
```

Expected: build succeeds with no errors.

## 2. What-if validation (azd preview)

```bash
azd env select <env-name> --no-prompt
azd provision --preview --no-prompt
```

Expected: no unplanned destructive changes.

## 3. Apply infrastructure and deploy

```bash
azd env select <env-name> --no-prompt
azd provision --no-prompt
azd deploy --no-prompt
```

Expected:

- infrastructure provisioning succeeds
- postprovision hook validates Container App state and `/health`
- deploy step succeeds (service deployment, if defined)

## 4. Restart recovery

```bash
az containerapp restart --name <app-name> --resource-group <rg>
az containerapp logs show --name <app-name> --resource-group <rg> --follow
```

Expected:

- service returns healthy
- queries and reactions recover automatically
- no checkpoint regression

## 5. Revision rollout

```bash
az deployment group create --resource-group <rg> --template-file azure/prod/main.bicep --parameters azure/prod/main-prod.bicepparam --parameters containerImage='<immutable-tag>'
az containerapp revision list --name <app-name> --resource-group <rg> --output table
```

Expected:

- new revision activates cleanly
- runtime state remains consistent

## 6. State-store outage simulation

Simulate transient PostgreSQL or Redis unavailability in a controlled non-production window.

Expected:

- error and checkpoint-age alerts fire
- no false success progression
- replay resumes from durable checkpoint after recovery

## 7. Replay burst test

Generate source changes while runtime cannot process, then restore.

Expected:

- backlog drains within objective
- p95 returns to baseline range after catch-up
