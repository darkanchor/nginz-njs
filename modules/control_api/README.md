# nginz_njs_control_api

Operator-facing control surface for nginx written in Gleam. This module is the Milestone 3 capstone for the scripted platform: it gives the repo one place to expose runtime state, inspection, and safe control actions across the modules that already have useful live behavior.

## Use Case

**The problem**: once a gateway grows beyond static config, operators need to inspect and adjust behavior without turning every change into “edit a file and reload nginx.” Feature flags, cache state, session facts, tracing summaries, and small control actions all become much more useful when they can be observed and managed through one coherent runtime surface.

**How it solves it**: this module gives the ecosystem a shared control face. Instead of each module inventing its own tiny admin dialect, `control_api` creates one operator-oriented surface for listing control routes, reading state, and performing small trusted control actions against runtime-backed modules. That makes the platform feel like a product, not just a set of unrelated building blocks.

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
- `/runtime/metrics/...` — render or describe shared metric values through one operator-facing surface
- `/runtime/tracing/...` — debug/summary surfaces over tracing state when appropriate

The current surface is intentionally small and JSON-first: it proves route inventory, health, flag inspection/write, and cache/session probes before broader control-plane ambitions.

## What is implemented

**`control_api/model.gleam`**
- `Endpoint` — named runtime endpoint descriptor
- `endpoints()` — stable route inventory for the current runtime surface
- `summary()` / `describe_all()` — human-readable endpoint summaries

**`control_api/response.gleam`**
- `json_object(fields)` — flat JSON object rendering helper
- `json_ok(fields)` — stable ok envelope for operational responses
- `json_error(message)` — stable error envelope for validation/runtime failures

**`control_api/flag.gleam`**
- `inspect(dict_name, flag_name)` — reads runtime-backed feature flag state
- `toggle(dict_name, flag_name, enabled, rollout_pct, ttl_s)` — writes flag state to the configured shared dict

**`control_api/probe.gleam`**
- `system_info()` — basic module/version/timestamp surface
- `cache_probe(dict_name)` — shared-dict reachability probe via `mlcache/shared`

**`control_api/session_probe.gleam`**
- `session_probe(dict_name)` — shared-dict reachability probe via `session/store`

**`control_api/metrics_handler.gleam`**
- `render_metric(...)` — builds and renders a StatsD line from query params via the shared `metrics` module
- `describe_metric(...)` — builds and describes a metric via the shared `metrics` module

**`control_api/router.gleam`**
- `describe_routes()` — route inventory adapter over `model.describe_all()`

**`nginz_njs_control_api.gleam`**
- `describe` — returns the stable route inventory
- `health` — returns a JSON health payload for the module
- `system_info` — returns module/version/timestamp runtime info
- `inspect_flag` — inspects a requested flag name from query parameters
- `toggle_flag` — writes a requested flag state to the configured shared dict
- `probe_cache` — checks whether an `mlcache` shared dict is reachable
- `probe_session` — checks whether a session shared dict is reachable
- `render_metric` — renders a StatsD metric line from query params
- `describe_metric` — describes a metric from query params

**Integration tests**
- `tests/basic/` — route description, health, system info, real flag write/read-back, cache/session probes, and metrics render/describe handlers with stock nginx

## Core abstractions

- `Endpoint` — reusable description of a runtime surface
- `json_object` / `json_ok` / `json_error` — deterministic JSON response helpers for the operator surface
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

        location /runtime/system {
            js_content main.system_info;
        }

        location /runtime/flag/set {
            js_content main.toggle_flag;
        }

        location /runtime/cache/probe {
            js_content main.probe_cache;
        }

        location /runtime/session/probe {
            js_content main.probe_session;
        }

        location /runtime/metrics/render {
            js_content main.render_metric;
        }

        location /runtime/metrics/describe {
            js_content main.describe_metric;
        }
    }
}
```

In production this surface should normally be internal-only, protected by network policy, mTLS, or an `auth_request` / `authz` gate.

## Detailed design direction

### Read first, write later

The first useful version of a runtime API is not unrestricted mutability. It is reliable introspection and narrow, well-scoped control actions.

So the intended sequencing is:

1. stable route inventory and health
2. deterministic read endpoints over existing module state
3. authenticated, explicitly supported write endpoints only after the contract settles
4. broader runtime families only when the ownership lines stay clean

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
- [x] keep the first surface small and deterministic while the contract settles

### Phase 2 — compose real module surfaces

Goal: turn the scaffold into a real operator-facing surface by composing the runtime-capable modules that already exist.

- [x] compose `feature_flags` runtime state with supported read/write contracts
- [x] compose `mlcache` and `session` inspection helpers where the ownership lines are clear
- [x] add JSON-oriented response surfaces for the operator contract
- [x] add a stable route/capability inventory that tools can consume programmatically
- [x] compose the shared `metrics` module into operator-facing render/describe endpoints

### Phase 3 — controlled writes and operator safety

Goal: move from preview-only actions to a supported internal control plane.

- [ ] add authenticated/operator-safe write paths only after the API contract is worth stabilizing
- [ ] document the expected auth/deployment patterns (`internal`, `auth_request`, mTLS, trusted network)
- [ ] add idempotent write semantics where runtime state can safely support them
- [ ] keep native-dependent control actions gated until the native side exposes stable primitives

### Phase 4 — capstone productization surface

Goal: make `control_api` the operator-facing glue that gives the rest of the ecosystem one coherent control face.

- [x] compose tracing/metrics summaries where the ownership boundary stays clean
- [ ] expose richer status/control surfaces for CI/CD and orchestration tooling
- [ ] keep the surface close to the value of nginx-plus `/api/` without pretending unsupported native controls already exist

## TDD plan

- [x] unit-test route inventory and response helpers
- [x] unit-test stable JSON response contracts
- [x] integration-test describe/health/flag/probe handlers via `tests/basic/`
- [x] integration-test composed `feature_flags` / `mlcache` / `session` read surfaces
- [ ] integration-test authenticated/operator-safe write paths once they exist

## Verification checklist

- [x] `bun scripts/test.js control_api`
- [x] `bun test modules/control_api/tests/basic/do.test.js`
- [x] `bun run build:module control_api`
- [x] integration proof against real runtime-backed module surfaces (`feature_flags`, `mlcache`, `session`)
- [x] integration proof that `control_api` composes the shared `metrics` module without inventing a second metrics dialect

## Current HTTP contract

- `GET /runtime/describe` returns plain-text route inventory.
- `GET /runtime/health` and `GET /runtime/system` return `200` JSON payloads.
- `GET /runtime/flag` and `GET /runtime/cache|session/probe` return `400` JSON errors when required query params are missing.
- `GET /runtime/flag?name=...` returns `200` with either an ok payload or an error payload when the named flag is absent.
- `GET /runtime/flag/set?...` returns `200` JSON describing the written flag state.
- `GET /runtime/metrics/render?...` returns a plain-text StatsD line or `400` with a plain-text validation error.
- `GET /runtime/metrics/describe?...` returns a plain-text metric summary.
