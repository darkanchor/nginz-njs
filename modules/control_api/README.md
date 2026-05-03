# nginz_njs_control_api

Operator-facing control surface for nginx written in Gleam. This module is the Milestone 3 capstone for the scripted platform: it gives the repo one place to expose runtime state, inspection, and safe control actions across the modules that already have useful live behavior.

## Use Case

**The problem**: once a gateway grows beyond static config, operators need to inspect and adjust behavior without turning every change into “edit a file and reload nginx.” Feature flags, cache state, session facts, tracing summaries, and small control actions all become much more useful when they can be observed and managed through one coherent runtime surface.

**How it solves it**: this module gives the ecosystem a shared control face. Instead of each module inventing its own tiny admin dialect, `control_api` creates one operator-oriented surface for listing control routes, reading state, previewing changes, and later performing controlled writes. That makes the platform feel like a product, not just a set of unrelated building blocks.

**When you would use this**: use it when nginx is acting like a programmable edge and you need a safe internal API for operations. That can mean reading a flag, checking cache/session state, exposing health or trace summaries, or driving small trusted control-plane actions from CI/CD or internal tooling.

## Why this belongs here

The native nginz notes call this out very directly: a unified runtime API is **njs scope**, not Zig scope. `design-commercial-gaps.md` frames it as the open-source analogue to nginx-plus `/api/` and explicitly says it should be "an njs library, not a native module." That makes it unusual in this repo: it is not just another feature module, it is a productization layer over the runtime-capable modules that already exist.

That is why `control_api` stays in Milestone 3 even though it feels partly like a handler family. The ecosystem boost is large enough to justify a dedicated module boundary, provided the reusable library surface stays real and does not collapse into a bag of route demos.

## Design goals

- keep endpoint descriptions and response contracts pure and reusable
- make runtime inspection/control handlers small, predictable, and easy to test
- build on top of existing scripted module surfaces first
- support read paths, preview paths, and eventually controlled write paths without turning into a second policy engine
- provide one stable operator-facing shape for the ecosystem instead of scattering admin patterns everywhere

## What this module is not

- not a replacement for `authz`; access control still belongs in `authz`
- not a replacement for per-module libraries like `feature_flags/state` or `mlcache/shared`
- not a native control plane for upstream balancing or other native-only primitives before those surfaces are real and stable
- not a second application framework embedded inside nginx

## Architectural role

`control_api` sits above existing foundations:

- `feature_flags` provides runtime-backed flag state and mutating handlers
- `mlcache` provides shared cache inspection primitives and lock semantics
- `session` provides lifecycle/state facts
- `request_tracing` and `metrics` provide structured operational data

`control_api` should not duplicate their ownership. Its job is to give them one coherent operator-facing contract.

The intended architecture is:

1. the owning module keeps its reusable domain library surface
2. `control_api` imports that surface and exposes a stable control contract
3. auth/access policy for the runtime endpoints composes through ordinary nginx + `authz`

## Target runtime surface

The long-term shape is closer to a tiny internal control plane than a random set of helpers. Likely endpoint families:

- `/runtime/describe` — route inventory and capability summary
- `/runtime/health` — runtime surface health and readiness
- `/runtime/flags/...` — inspect and mutate supported feature flag state
- `/runtime/cache/...` — inspect cache config/state and perform safe invalidation operations where supported
- `/runtime/session/...` — inspect lifecycle/config summaries and safe operational facts
- `/runtime/tracing/...` — debug/summary surfaces over tracing state when appropriate

The module should begin with text or simple JSON responses and only add richer contracts once the ownership lines are proven.

## What is implemented

**`control_api/model.gleam`**
- `Endpoint` — named runtime endpoint descriptor
- `demo_endpoints()` — stable scaffold endpoint list
- `summary()` — human-readable endpoint summary

**`control_api/response.gleam`**
- `ok(body)` — stable ok response text wrapper
- `error(body)` — stable error response text wrapper
- `kv(key, value)` — helper for simple key/value lines

**`control_api/router.gleam`**
- `describe_routes()` — stable route inventory for scaffold testing

**`nginz_njs_control_api.gleam`**
- `describe` — returns the stable route inventory
- `health` — returns a small ok runtime status
- `inspect_flag` — inspects a requested flag name from query parameters
- `toggle_flag_preview` — returns a preview of a runtime flag write request without persisting anything yet

**Integration tests**
- `tests/basic/` — route description, health, and preview handlers with stock nginx

## Core abstractions

- `Endpoint` — reusable description of a runtime surface
- `ok` / `error` / `kv` — tiny response-formatting helpers for deterministic control responses
- `describe_routes` — stable route listing for documentation and tests

Architectural rule: `control_api` should expose and compose existing runtime-capable module surfaces; it should not replace their core libraries or become a second application framework.

## Typical nginx usage

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8888;

        location /runtime/describe {
            js_content main.describe;
        }

        location /runtime/health {
            js_content main.health;
        }

        location /runtime/flag {
            js_content main.inspect_flag;
        }

        location /runtime/flag/preview {
            js_content main.toggle_flag_preview;
        }
    }
}
```

In production this surface should normally be internal-only, protected by network policy, mTLS, or an `auth_request` / `authz` gate.

## Detailed design direction

### Read first, write later

The first useful version of a runtime API is not full mutability. It is reliable introspection and previewability.

So the intended sequencing is:

1. stable route inventory and health
2. deterministic read endpoints over existing module state
3. preview endpoints for write operations
4. authenticated, explicitly supported write endpoints only after the contract settles

That keeps the module useful early without making unsafe promises.

### Compose, do not absorb

If `feature_flags` already owns how flag state is loaded/saved, `control_api` should import and expose that behavior, not recreate a second flag engine. The same is true for cache, session, and tracing surfaces.

### Keep auth outside the module core

`control_api` should expose operational actions; it should not decide who is allowed to use them. That belongs to nginx config and `authz`. This keeps the module reusable in different trust models.

### Prefer stable response contracts

The runtime surface is valuable only if tooling can rely on it. That means the response model should trend toward stable schemas rather than ad-hoc strings once the scaffold phase is over.

## Phased implementation plan

### Phase 1 — establish the control-surface model ✓

- [x] add reusable endpoint/response modeling helpers
- [x] keep the first scaffold inspection-focused and deterministic
- [x] keep write operations in preview mode until the control contract is clearer

### Phase 2 — compose real module surfaces

Goal: turn the scaffold into a real operator-facing surface by composing the runtime-capable modules that already exist.

- [ ] compose `feature_flags` runtime state with supported read/write contracts
- [ ] compose `mlcache` and `session` inspection helpers where the ownership lines are clear
- [ ] add JSON-oriented response surfaces once the text scaffold proves the operator stories
- [ ] add a stable route/capability inventory that tools can consume programmatically

### Phase 3 — controlled writes and operator safety

Goal: move from preview-only actions to a supported internal control plane.

- [ ] add authenticated/operator-safe write paths only after the API contract is worth stabilizing
- [ ] document the expected auth/deployment patterns (`internal`, `auth_request`, mTLS, trusted network)
- [ ] add idempotent write semantics where runtime state can safely support them
- [ ] keep native-dependent control actions gated until the native side exposes stable primitives

### Phase 4 — capstone productization surface

Goal: make `control_api` the operator-facing glue that gives the rest of the ecosystem one coherent control face.

- [ ] compose tracing/metrics summaries where the ownership boundary stays clean
- [ ] expose richer status/control surfaces for CI/CD and orchestration tooling
- [ ] keep the surface close to the value of nginx-plus `/api/` without pretending unsupported native controls already exist

## TDD plan

- [x] unit-test route inventory and response helpers
- [x] unit-test preview rendering for runtime flag inspection/write intent
- [x] integration-test describe/health/preview handlers via `tests/basic/`
- [ ] unit-test stable JSON response contracts before adding real structured API responses
- [ ] integration-test composed `feature_flags` / `mlcache` / `session` read surfaces
- [ ] integration-test authenticated/operator-safe write paths once they exist

## Verification checklist

- [x] `bun scripts/test.js control_api`
- [x] `bun test modules/control_api/tests/basic/do.test.js`
- [x] `bun run build:module control_api`
- [ ] integration proof against one real runtime-backed module surface (`feature_flags` first)
