# Changelog

## 2026-05-04

### Added

- Azure Container Apps durable runtime storage for Drasi config and REDB state in `azure/modules/drasi-runtime.bicep`.
- Azure Files-backed startup bootstrap logic that initializes `server.yaml` only when missing, then preserves runtime API mutations across restarts.
- Default runtime `stateStore` configuration for REDB persistence in:
    - `azure/prod/main.bicep`
    - `azure/prod/main-prod.bicep`
    - `azure/prod/main-prod.bicepparam`
- Matching durable Azure Container Apps capability in `forks/drasi-server/azure/main.bicep` for upstream merge readiness.

### Changed

- Container startup command no longer overwrites runtime config on every restart.
- Runtime container now mounts a dedicated Azure File volume at `/drasi-persist`.

### Upstream comparison note

Compared with `https://github.com/ruokun-niu/drasi-server/tree/drasi-server-aca/azure`, this repository now includes Azure Container Apps durability capabilities that are not present upstream yet:

- Managed Environment storage registration (`Microsoft.App/managedEnvironments/storages`)
- Azure Files volume mount for persistent runtime config
- Bootstrap-once config initialization behavior
- Default REDB state store path on durable storage

These changes are intended to preserve API-created sources, queries, and reactions after Container Apps revision restarts.
