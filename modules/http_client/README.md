# nginz_njs_http_client

Typed `ngx.fetch()` wrapper for nginx written in Gleam — the highest-priority Tier 1 module.

## Roadmap position

`http_client` is the foundation module in `ROADMAP.md`. It makes `workflow` and other upstream-calling modules more ergonomic without introducing any native dependency.

## Design goals

- keep request construction pure and typed
- make auth headers, timeouts, method selection, and body first-class values
- keep nginx effects at the edge and core request shaping in Gleam
- the pure `Request` model is the stable input to all execution helpers

## What is implemented (substantial Phase 1–5 foundations)

**`http_client/client.gleam`** — pure request model
- `Method` — 7 HTTP methods as a sum type (Get, Head, Post, Put, Patch, Delete, Options)
- `Request` — typed descriptor with headers, auth, body, query params, timeout
- 8 builder helpers
- `build_url`, `summary` — deterministic for testing

**`http_client/fetch.gleam`** — execution layer
- `Response(status: Int, body: String)` — typed HTTP response
- `ClientError` — `FetchFailed`, `Timeout`, `InvalidUrl`, `InvalidRequest`
- `execute` — maps pure `Request` → njs fetch → `Result(Response, ClientError)`; today it emits `FetchFailed`, while richer variants are reserved for later policy/validation layers
- Response helpers: `is_success`, `is_client_error`, `is_server_error`, `is_redirect`, `status_text`

**`http_client/policy.gleam`** — retry composition
- `RetryPolicy` — `NoRetry` or `Retry(max_attempts)` (immediate only)
- `Policy` — composable execution policy wrapper
- `execute_with_policy` — runs `execute()` with retry semantics

**`http_client/middleware.gleam`** — composable request transformations
- `Middleware` — pure `fn(Request) -> Request`
- `stack` — left-to-right composition
- Pre-built: `bearer_token`, `add_header`, `json_content_type`, `timeout_ms`

**`http_client/response.gleam`** — body extraction helpers
- `body_or`, `body_if_success`, `body_if_status`

**`nginz_njs_http_client.gleam`** — njs entry point (5 handlers)
- `demo`, `fetch_demo`, `request_demo`, `middleware_demo`, `retry_demo`

**Integration tests** — 5 scenarios with stock nginx, no native deps.

## Core abstractions

The architectural rule for this module: request construction and response interpretation stay pure; only `ngx.fetch()` execution touches nginx/njs runtime effects.

## Composition with other modules

`workflow/pipeline.gleam` consumes `http_client/fetch` as a building block — `fetch_step` delegates to `execute()` and maps all `ClientError` variants. This is the intended pattern: `http_client` owns execution; downstream modules own orchestration.

## Scripted core vs optional native integration

### Scripted core (implemented today)

- request construction, headers, body, query params
- auth/header shaping
- response classification
- builder pipeline pattern

### Future refinement areas

- retry policy wrappers (`NoRetry`, `ConstantBackoff`, `ExponentialBackoff`)
- timeout enforcement
- middleware-style auth/header injection
- JSON body helpers

## Phased implementation plan

### Phase 1 — stabilize the pure request model ✅

- [x] expand `Request` to model headers, optional body, and query parameters explicitly
- [x] keep method, timeout, and auth configuration as typed fields
- [x] add pure helpers for common auth/header patterns
- [x] keep deterministic rendering/debug helpers

### Phase 2 — add the first real `ngx.fetch()` adapter ✅

- [x] add `Response` type with status and body
- [x] add `execute()` mapping `Request` → `ngx.fetch()` → `Result(Response, ClientError)`
- [x] narrow first execution milestone: no retry, no hidden defaults
- [x] demo handler proving the runtime seam

### Phase 3 — add typed error and response shaping ✅

- [x] define `ClientError` cases: `FetchFailed`, `Timeout`, `InvalidUrl`, `InvalidRequest`
- [x] add response helpers: `is_success`, `is_client_error`, `is_server_error`, `is_redirect`, `status_text`
- [x] keep parsing/classification separate from request execution
- [x] workflow module consumes all error variants

### Phase 4 — add policy wrappers around execution (partially in place)

- [x] add typed retry policy values (`RetryPolicy`, `Policy`)
- [x] pass timeout hints through `ngx.fetch()` options
- [x] add composable middleware for auth/header injection
- [x] immediate retry with `execute_with_policy` (backoff delay blocked by njs timer context)

### Phase 5 — prepare for ecosystem reuse (partially in place)

- [x] document patterns for use from `workflow`, `authz`, `webhook`, and future modules
- [x] add middleware-style composition (`Middleware`, `stack`)
- [x] add response body helpers (`body_or`, `body_if_success`, `body_if_status`)
- [x] examples showing pure request construction reused across multiple handlers

## TDD plan

- [x] unit-test request builders and pure model transformations (34 tests)
- [x] integration test for real `ngx.fetch()` path (5 scenarios)
- [x] retries and policy wrappers behind their own test cases
- [x] integration tests distinguish stock-nginx behavior from native-backed scenarios

## Verification checklist

- [x] `bun scripts/test.js http_client` — 34 unit tests pass
- [x] `bun test modules/http_client/tests/basic/do.test.js` — 5 integration tests pass
- [x] `bun run test` — all 83 unit + 25 integration tests pass across all modules
