# Production multi-replica scale-out architecture

## Goal

Define a production-safe architecture for scaling Drasi on Azure Container Apps beyond one replica while preserving deterministic replay and durable state.

## Current baseline

- Single runtime app with `minReplicas: 1` and `maxReplicas: 1`.
- Durable state path is `stateStore.kind: redb` at `/drasi-persist/state.redb`.
- Azure Files provides durable config and state volume for restart and revision survivability.
- Redis is used for cache and acceleration, not as the authoritative state store.

This baseline is correct for single replica, but multi-replica production needs a stricter tiered state model.

## Target architecture

### 1. Split control plane and data plane

Use two Container Apps instead of one combined runtime role.

- `drasi-api` (control plane)
    - Handles source, query, and reaction lifecycle APIs.
    - Persists configuration and version metadata in PostgreSQL.
    - Runs at a stable replica count for availability.
- `drasi-worker` (data plane)
    - Executes source ingestion, query processing, and reaction delivery.
    - Scales horizontally based on lag and throughput signals.

### 2. Partition ownership and leasing

Introduce explicit partition ownership for worker scale-out.

- Assign each partition to one active worker at a time.
- Store lease owner, lease epoch, and expiry in PostgreSQL.
- Require heartbeat renewal and lease timeout recovery.
- Rebalance through controlled lease transfer, not opportunistic takeover.

### 3. State strategy

- Tier 1 local ephemeral state (`emptyDir`)
    - Use for replay buffers, temporary joins, and short-lived worker scratch data.
    - Treat as disposable on restart.
- Tier 2 shared ephemeral cache (Redis)
    - Use for dedupe keys, hot read caching, and rebalance hints.
    - Require TTL and bounded memory policy.
- Tier 3 authoritative durable state (PostgreSQL)
    - Store checkpoints, partition ownership, lease metadata, and replay control metadata.
    - Use as the only commit authority for correctness-critical decisions.

### 3.1 Write authority rules

- Only PostgreSQL can advance authoritative checkpoints and ownership epochs.
- Redis and `emptyDir` can accelerate reads and recomputation, but cannot commit authority state.
- Worker restart must recover from PostgreSQL checkpoint state, not from cache state.

Do not use a shared multi-writer file as the single source of truth.

### 4. Event ingress and worker scaling

- Prefer partitioned ingress for production scale (for example, Event Hubs).
- Scale workers using lag-driven and throughput-driven triggers.
- Keep control plane scaling independent from worker autoscaling.

### 5. Observability and control loops

Required telemetry for production scale-out:

- Partition lag by source and partition
- Lease churn and lease steal attempts
- Replay duration and replay success rate
- Conflict count and conflict resolution latency
- Checkpoint age and checkpoint regression count
- Reaction delivery success and retry depth

## Recommended KEDA trigger directions

Use these as starting points and tune with production data.

- Worker scale-out signal: sustained partition lag growth.
- Worker scale-in guard: minimum warm worker count to avoid rebalance thrash.
- Burst guard: max scale step per interval to reduce lease churn.
- Cooldown: long enough to finish checkpoint and ownership stabilization.

## Failure modes and handling

| Failure mode                          | Expected behavior                     | Required mitigation                                        |
| ------------------------------------- | ------------------------------------- | ---------------------------------------------------------- |
| Worker crash with active leases       | Lease expires and ownership transfers | TTL heartbeat lease model and replay-safe resume           |
| Duplicate ownership of same partition | Potential conflicting writes          | Single-owner lease validation and epoch checks             |
| Checkpoint regression                 | Replay inconsistency risk             | Monotonic checkpoint constraints and rejection path        |
| Redis outage                          | Cache degradation only                | Keep authoritative state in PostgreSQL, fail soft on cache |
| `emptyDir` loss on restart            | Local scratch state is discarded      | Rebuild from PostgreSQL checkpoint and replay              |
| Revision rollout during load          | Temporary ownership movement          | Controlled rollout with lease stabilization checks         |

## Rollout plan

### Stage 0: Stabilize single-replica baseline

- Keep current topology.
- Ensure state contract checks pass consistently.
- Capture baseline latency and checkpoint metrics.

### Stage 1: Introduce ownership model behind a flag

- Add partition and lease tables.
- Add heartbeat and TTL expiry handling.
- Keep one worker replica while validating ownership logic.

### Stage 2: Controlled dual-replica test

- Run two workers in a controlled environment.
- Validate deterministic replay and conflict behavior.
- Record evidence for readiness gates.

### Stage 3: Production canary scale-out

- Increase worker max replicas gradually.
- Apply SLO gates and rollback guardrails.
- Promote only after repeated deterministic validation.

## Go-live checklist mapped to readiness gates

This checklist extends `docs/drasi-state-contract.md`.

### Gate A: Partition ownership

- [ ] Ownership map exists for all source partitions.
- [ ] One active owner per partition verified in steady state.
- [ ] Lease failover tested under worker restart.

### Gate B: Replay determinism

- [ ] Two consecutive replay runs produce identical result snapshots.
- [ ] Checkpoint progression is monotonic during rebalance.
- [ ] Restart plus revision rollout yields identical end state.
- [ ] Restart with `emptyDir` loss still converges to the same end state.

### Gate C: Conflict handling

- [ ] Conflict strategy implemented and tested under concurrency.
- [ ] Zero lost updates in conflict simulation.
- [ ] Conflict metrics and alerts are active.
- [ ] Conflicts do not promote Redis or `emptyDir` data to authoritative state.

### Promotion gate

- [ ] `/health` remains stable during scale events.
- [ ] `/api/v1/docs/` and `/api/v1/openapi.json` remain available during scale events.
- [ ] Source, query, and reaction lifecycle operations pass during rebalancing.
- [ ] Redis outage test confirms degraded performance without correctness loss.
- [ ] Rollback plan validated for replica reduction and lease reset.

## Decision rule

- Keep single-replica mode while any required gate is incomplete.
- Enable production multi-replica only after all gates pass with retained evidence artifacts.
