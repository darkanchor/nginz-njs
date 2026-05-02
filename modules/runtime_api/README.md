# nginz_njs_runtime_api

Operator-facing runtime inspection and control surface for nginx written in Gleam. This module is meant to sit on top of existing scripted foundations such as `feature_flags`, `mlcache`, `session`, `metrics`, and `request_tracing`, giving them one cleaner operational face.

## Use Case

**The problem**: once runtime-capable features exist, operators need a reliable way to inspect and control them. Otherwise the useful state is there, but it is scattered across ad-hoc handlers, query-string demos, and one-off nginx snippets.

**How it solves it**: this module creates a reusable control-plane shape for runtime state. It keeps responses predictable, lets small inspection/control handlers speak one language, and gives the repo a place to grow operator-facing surfaces without forcing every module to invent its own mini admin API. That makes the platform feel more like one product and less like a pile of unrelated demos.

**When you would use this**: use it when you want a controlled endpoint for looking at runtime state, toggling a simple flag, inspecting cache/session settings, or exposing a small operational surface to trusted internal users.

## Roadmap position

`runtime_api` is a Milestone 3 standalone module in `ROADMAP.md`. It exists because the repo now has enough runtime-capable building blocks that they deserve a shared operator/control surface rather than scattered demos.

## Design goals

- keep endpoint descriptions and response shaping pure and reusable
- make runtime inspection/control handlers small and predictable
- build on existing scripted module surfaces first
- avoid becoming a second policy engine or a duplicate config system

## What is implemented

**`runtime_api/model.gleam`**
- `Endpoint` — named runtime endpoint descriptor
- `demo_endpoints()` — stable scaffold endpoint list
- `summary()` — human-readable endpoint summary

**`runtime_api/response.gleam`**
- `ok(body)` — stable ok response text wrapper
- `error(body)` — stable error response text wrapper
- `kv(key, value)` — helper for simple key/value lines

**`runtime_api/router.gleam`**
- `describe_routes()` — stable route inventory for scaffold testing

**`nginz_njs_runtime_api.gleam`**
- `describe` — returns the stable route inventory
- `health` — returns a small ok runtime status
- `inspect_flag` — inspects a requested flag name from query parameters
- `toggle_flag_preview` — returns a preview of a runtime flag write request without persisting anything yet

**Integration tests**
- `tests/basic/` — route description, health, and preview handlers with stock nginx

## Core abstractions

- `Endpoint` — reusable description of a runtime surface
- `ok` / `error` / `kv` — tiny response-formatting helpers
- `describe_routes` — stable route listing for documentation and tests

Architectural rule: `runtime_api` should expose and compose existing runtime-capable module surfaces; it should not replace their core libraries or become a second application framework.

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

## Phased implementation plan

### Phase 1 — establish the control-surface model ✓

- [x] add reusable endpoint/response modeling helpers
- [x] keep the first scaffold inspection-focused and deterministic
- [x] keep write operations in preview mode until the control contract is clearer

### Phase 2 — compose real module surfaces (future)

- [ ] compose `feature_flags` runtime state with supported read/write contracts
- [ ] compose `mlcache` and `session` inspection helpers where the ownership lines are clear
- [ ] add authenticated/operator-safe write paths only after the API contract is worth stabilizing
- [ ] add JSON-oriented response surfaces once the text scaffold proves the operator stories

## TDD plan

- [x] unit-test route inventory and response helpers
- [x] unit-test preview rendering for runtime flag inspection/write intent
- [x] integration-test describe/health/preview handlers via `tests/basic/`

## Verification checklist

- [ ] `bun scripts/test.js runtime_api`
- [ ] `bun test modules/runtime_api/tests/basic/do.test.js`
- [ ] `bun run build:module runtime_api`
