# nginz_njs_circuit_breaker_policy

## Status

**No longer a standalone Milestone 2 package. Merge target: `workflow` (with possible helper reuse in response-shaping code).**

The architecture review found that the meaningful part of this design is not “read `$ngz_circuit_state` and serve a 503 body.” The meaningful part is resilience composition: skip a step when the circuit is open, recover with fallback data, and integrate cached or degraded responses into orchestration.

## Why the standalone package was demoted

As a sibling package, `circuit_breaker_policy` is too adapter-heavy:

- one native variable
- one narrow content-phase fallback story
- static 503 body rendering as the visible product

That is not the strongest product boundary. The reusable value already points straight at `workflow`, where retry, recovery, timeout, and fallback composition already live.

## What should move where

### Move into `workflow`

- circuit-aware step wrappers
- skip / recover combinators informed by circuit state
- degraded-mode orchestration and cached fallback integration

### Optional helper reuse elsewhere

- response payload helpers can be shared or composed through existing response-shaping surfaces such as `response_transform` or local adapter code

The important thing is not to preserve a separate package just because the native module exposes `$ngz_circuit_state`.

## Architectural lesson

This module fails the stronger library-first test as a top-level product, but its resilience primitives are still useful once attached to the module that already owns orchestration semantics. The right abstraction is “circuit-aware workflow composition,” not “a standalone wrapper around one circuit variable.”

## Outcome for the roadmap

`circuit_breaker_policy` is removed as a planned standalone package. Its surviving work is now part of Milestone 2’s `workflow` extension track.
