# nginz_njs_ratelimit_policy

## Status

**Aborted as a standalone Milestone 2 module.**

The design review uncovered a hard nginx phase constraint: native `ratelimit` decisions happen in ACCESS phase, and the request-local decision state is not reliably readable from a `js_content` handler reached through `error_page`. That breaks the core package pitch of “standalone scripted rate-limit response shaping” as a general reusable module.

## Why it was aborted

Two hard facts changed the architectural judgment:

1. `return` and other REWRITE-phase directives can bypass ACCESS-phase handlers entirely.
2. ACCESS-phase variable state can be lost across `error_page` internal redirects, so a deny-path `js_content` handler cannot safely reconstruct the native ratelimit decision.

Those facts mean the original package boundary was wrong. The module was too centered on adapter mechanics that nginx phase rules do not guarantee.

## What survives conceptually

Some tiny ideas remain useful, but not as a top-level package:

- simple 429 body renderers
- header-pair helpers for static `Retry-After` / `X-RateLimit-*` output
- documentation about phase-safe native ratelimit integration patterns

If these helpers are kept, they should live beside the modules that actually consume them, or remain as local adapter code, not as a standalone product surface.

## Where the useful behavior belongs instead

- **Direct nginx config first** for native ratelimit enforcement and header injection
- **`authz`** when rate-limit facts need to participate in a broader policy engine and the phase model is actually valid for the chosen path
- **`workflow`** only for fallback or degraded-mode composition that is independent of reading deny-path ratelimit state through `error_page`

## Design flaw summary

The detailed hard findings that caused this abort are preserved here because they apply beyond this package:

### Flaw 1: `return` in a location with ACCESS-phase modules is silently broken

`return` runs in REWRITE phase, before native ACCESS-phase handlers like `ratelimit`, `waf`, or `jwt`. Any location that mixes `return` with those directives can accidentally skip the native module entirely.

### Flaw 2: ACCESS-phase variables are lost in `error_page` internal redirects

The native ratelimit decision can disappear across `error_page 429 = @name;` redirects because the variable backing is request-context-local. A redirected `js_content` handler may see an empty value instead of the original deny decision.

## Outcome for the roadmap

`ratelimit_policy` is removed from the Milestone 2 package list.

The general lesson is broader than ratelimiting itself: **a native variable is not a sufficient reason to mint a standalone scripted package.** A package must first prove that its reusable Gleam library surface survives nginx phase realities.

The open njs PR #1044 (`js_access` + request body/form reads) does not change this conclusion. It may improve future scripted access-phase policy in modules like `authz`, but it does not by itself fix native ratelimit deny-path context loss across `error_page` redirects.
