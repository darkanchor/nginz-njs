# nginz_njs_health_gateway

## Status

**Deferred. Not part of the near-term standalone Milestone 2 package set.**

The review conclusion is not that `health_gateway` is impossible. It is that the current package is premature. Native `healthcheck` already exposes readiness, liveness, and backend-count facts directly, so a scripted package only becomes justified when we need aggregation or policy that the native surface cannot already express cleanly.

## Why it was deferred

Right now the design mixes two stories:

1. a real pure-library aggregation model over backend health data
2. a still-lagging adapter built around simulated `$health_backends` input even though `$health_*` now exists natively

That means the package is neither a clean wrapper over the real native surface nor yet a proven multi-source aggregation product. Deferring it is more honest than pretending it is a near-term sibling package.

## What would justify reviving it

Bring `health_gateway` back as a standalone module only when at least one of these becomes concrete:

- multi-source health aggregation across native `healthcheck`, service discovery, cache state, and scripted policy inputs
- custom readiness semantics that combine health with rollout/session/policy context
- cache-backed stale/refresh behavior that native health endpoints do not already cover
- routing decisions that genuinely need a reusable `AggregateStatus` / `GateDecision` library beyond simple native readiness variables

Without one of those, the native surface is already sufficient and a package would mostly be a wrapper.

## What survives conceptually

The pure library ideas are still sound:

- `AggregateStatus`
- `GateDecision`
- reusable health response rendering
- future aggregation and caching interfaces

But they are deferred until a real consumer proves the package boundary.

## Current recommendation

- use native `$health_*` variables directly for baseline readiness/liveness work
- keep richer health aggregation as a deferred design note
- avoid investing in a standalone package until the multi-source use case is real

## Outcome for the roadmap

`health_gateway` moves out of the core Milestone 2 package list and into the deferred follow-on section.
