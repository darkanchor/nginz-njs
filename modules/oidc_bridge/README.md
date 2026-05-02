# nginz_njs_oidc_bridge

## Status

**No longer a standalone Milestone 2 package. Merge target: `authz` + `feature_flags` + `session`.**

The review conclusion is that `oidc_bridge` does contain useful mapping logic, but not enough standalone product identity to justify a separate package. Its abstractions already sit beside modules that own policy (`authz`), rollout identity (`feature_flags`), and session binding (`session`).

## Why the standalone package was demoted

As a separate module, `oidc_bridge` mostly acts as plumbing:

- map OIDC claims into authz-compatible claims
- derive per-user flag keys
- create session-binding metadata

Those are real tasks, but each one points naturally to an existing module boundary. Leaving them in a separate package adds cognitive overhead without adding a stronger reusable surface.

## What should move where

### Move into `authz`

- OIDC claim extraction and mapping into the policy context
- identity adapters used by the main policy engine

### Move into `feature_flags`

- OIDC subject → `ByUserId` key resolution for rollout identity

### Move into `session`

- session-binding helpers when OIDC-authenticated identity needs persistence or lifecycle integration

## Scope discipline

This demotion also prevents the package from drifting into too many jobs at once. OIDC flow handling remains native. Token refresh, session lifecycle, and policy consumption should stay with the modules that already own those concerns.

The open njs PR #1044 (`js_access` + request body/form reads) may eventually simplify how OIDC-derived identity is consumed inside `authz`, especially for pre-content redirect or gate flows. It is only a future enabler for the merge path, not a reason to restore `oidc_bridge` as a standalone package.

## Outcome for the roadmap

`oidc_bridge` is removed as an independent package. Its surviving work is now tracked inside the existing foundation modules that actually consume the identity information.
