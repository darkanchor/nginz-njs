# nginz_njs_canary_policy

## Status

**No longer a standalone Milestone 2 package. Merge target: `feature_flags` + `session`.**

The review conclusion is that `canary_policy` is too thin as an independent module. Reading `$ngz_canary`, setting `X-Canary`, and logging the result is adapter glue, not a strong standalone product surface.

## Why the standalone package was demoted

The real value here is not header tagging. The real value is:

- canary-aware rollout overrides
- sticky assignment across requests
- experimentation identity that composes with feature flags and session state

Those concerns already belong naturally in `feature_flags` and `session`. Keeping them as a separate top-level module would create a package boundary around the weakest part of the design.

## What should move where

### Move into `feature_flags`

- canary-aware override helpers
- rollout-specific decision metadata
- any reusable mapping from native canary decisions into flag-evaluation context

### Move into `session`

- sticky canary assignment serialization
- persistence / lookup of canary assignment when session-backed identity is involved

### Keep only as optional adapter examples

- `X-Canary` request/response tagging
- canary decision logging

Those examples can live in docs or tiny adapter snippets without justifying a full package.

## Architectural lesson

The ratelimit review forced a stricter standard across Milestone 2: a package must justify its reusable Gleam surface, not merely wrap one native variable with a `js_content` handler. `canary_policy` fails that test as a sibling package, but its library fragments are still valid when absorbed into the foundations that already own rollout and identity.

## Outcome for the roadmap

`canary_policy` is no longer planned as an independent package. Its useful behavior is now tracked as:

- experimentation identity work in `feature_flags`
- sticky rollout state in `session`
- optional thin handler examples only where needed
