# Drasi state contract

## Goal

Define where state lives, which parts are authoritative, and what is currently supported in this repository for Azure Container Apps.

## State classes

| State class        | Example                                     | Authoritative store                               | Durability requirement                    |
| ------------------ | ------------------------------------------- | ------------------------------------------------- | ----------------------------------------- |
| Runtime config     | Sources, queries, reactions                 | Runtime config file persisted on Azure Files      | Must survive restart and revision rollout |
| Checkpoints        | CDC offsets, replay position                | Drasi runtime state store (`redb`) on Azure Files | Must be monotonic and durable             |
| Materialized state | Query result indexes and derived state      | Drasi runtime state store (`redb`) on Azure Files | Must survive restart and revision rollout |
| Hot cache          | Short-lived acceleration and dedupe support | Redis                                             | Rebuildable                               |
| Ephemeral compute  | In-flight buffers                           | Container memory                                  | Rebuildable                               |

## State backend options

| Option                                        | Summary                                                                | Replica profile                                      | Durability profile                       | Status in this repo             |
| --------------------------------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------- | ---------------------------------------- | ------------------------------- |
| Container-local filesystem only               | State is written inside container writable layer                       | Single replica only                                  | Lost on restart or revision swap         | Not supported for production    |
| `redb` on Azure Files                         | State is written to `/drasi-persist/state.redb` on mounted Azure Files | Single replica by default                            | Survives restart and revision rollout    | Current default                 |
| Redis only                                    | Redis holds runtime state directly                                     | Can scale, but requires strict consistency design    | Depends on Redis availability and policy | Not used as authoritative state |
| Mixed (`redb` authoritative plus Redis cache) | Durable state in `redb`, Redis used for cache and acceleration         | Single replica default, scale-out planned separately | Durable state remains on `redb`          | Current direction               |

## Replica support options

### Single replica

Single replica is the current production mode. It avoids concurrent writers to the same state file and keeps replay behavior deterministic.

### Multiple replicas

Multiple replicas are a planned mode, not the current default. Safe scale-out requires all of the following:

- Explicit partition ownership for sources, queries, and reactions.
- Deterministic replay across revisions and replica restarts.
- Conflict-safe state writes with clear ownership boundaries.
- Verified failover behavior under restart and revision transitions.

Until these are proven, scale is pinned to one replica.

### Multi-replica readiness checklist (high priority)

Use this checklist as the deployment gate before changing `maxReplicas` above `1`.

#### Gate A: Partition ownership

- [ ] Every source has an explicit ownership model documented.
- [ ] Query and reaction execution ownership is deterministic per partition.
- [ ] No partition can be processed by multiple active writers at the same time.
- [ ] Failover ownership transfer is defined and tested.

Exit criteria:

- Ownership map exists and is version controlled.
- Failover test shows only one active owner per partition during steady state.

#### Gate B: Replay determinism

- [ ] Replay of the same event sequence yields the same materialized results across replicas.
- [ ] Restart and revision rollout tests produce identical end state for sources, queries, and reactions.
- [ ] Checkpoint progression remains monotonic under rebalance conditions.
- [ ] Out-of-order and duplicate event handling behavior is verified.

Exit criteria:

- Two consecutive replay runs pass with identical result snapshots.
- Checkpoint audit shows no regressions after restart and re-assignment.

#### Gate C: Conflict handling

- [ ] Write conflict strategy is defined (single writer, lease, or compare-and-swap equivalent).
- [ ] Concurrent write simulations are executed for hot partitions.
- [ ] Conflict resolution does not lose committed state.
- [ ] Conflict telemetry is emitted and alert thresholds are defined.

Exit criteria:

- Conflict simulation completes with zero lost updates.
- Alerts fire correctly when conflict rate exceeds threshold.

#### Final promotion gate

- [ ] `/health` is stable during scale events.
- [ ] `/api/v1/docs/` and `/api/v1/openapi.json` remain available during scale events.
- [ ] Component and event visibility checks continue to pass during rebalance.
- [ ] Source, query, and reaction lifecycle operations remain successful during and after scale transitions.

Decision rule:

- Keep single replica if any gate above is incomplete.
- Increase replicas only after all gates pass and evidence is retained in deployment artifacts.

## Current implementation in this repository

### Runtime state path

- `stateStore.kind` is `redb`.
- `stateStore.path` is `${STATE_STORE_PATH:-/drasi-persist/state.redb}`.
- Source of runtime config is `azure/prod/main-prod.bicep` and `azure/prod/main-prod.bicepparam`.

### Durable mount and startup behavior

- Azure Files share is mounted at `/drasi-persist` in `azure/modules/drasi-runtime.bicep`.
- Startup command copies `server.yaml` from secret volume only when `/drasi-persist/server.yaml` is missing.
- Runtime then starts with `drasi-server --config /drasi-persist/server.yaml`.

This means API-created runtime mutations persist across restarts because config and state are stored on Azure Files.

### Redis role

- Redis is provisioned in `azure/modules/redis-runtime.bicep`.
- Redis credentials are injected through Key Vault-backed secrets.
- Redis is currently treated as cache and acceleration support, not as the only durable source of truth.

### Replica settings

- Current scale configuration is `minReplicas: 1` and `maxReplicas: 1` in `azure/modules/drasi-runtime.bicep`.

## Invariants

1. Durable state writes happen before checkpoint advancement.
2. API-created runtime mutations persist in durable storage.
3. Container-local writable layer is never the only source of truth.
4. Replay behavior is deterministic for repeated validation runs.

## Verification checks

Run these checks after deploys, restarts, and revision rollouts.

1. `GET /health` returns HTTP 200.
2. `GET /api/v1/docs/` returns HTTP 200.
3. `GET /api/v1/openapi.json` returns HTTP 200.
4. Runtime components are visible through instance APIs, and event stream checks confirm lifecycle activity.
5. A created source, query, and reaction still exist after restart.
