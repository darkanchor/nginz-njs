# nginz_njs_http_client

Typed `ngx.fetch()` wrapper for nginx written in Gleam — the highest-priority Tier 1 module.

## Roadmap position

`http_client` is the foundation module in `ROADMAP.md`. It makes `workflow` and other upstream-calling modules more ergonomic without introducing any native dependency.

## Design goals

- keep request construction pure and typed
- make auth headers, timeouts, method selection, and body first-class values
- keep nginx effects at the edge and core request shaping in Gleam
- the pure `Request` model is the stable input to all execution helpers

## What is implemented (Phases 1–3 complete)

**`http_client/client.gleam`** — pure request model
- `Method` — 7 HTTP methods as a sum type (Get, Head, Post, Put, Patch, Delete, Options)
- `Request` — typed descriptor with headers, auth, body, query params, timeout
- 8 builder helpers: `with_method`, `with_header`, `with_headers`, `with_bearer_token`, `with_body`, `with_query_param`, `with_query_params`, `with_timeout`
- `build_url` — assembles URL with query params
- `summary` — deterministic rendering for testing (17 unit tests)

**`http_client/fetch.gleam`** — execution layer
- `Response(status: Int, body: String)` — typed HTTP response
- `ClientError` — `FetchFailed`, `Timeout`, `InvalidUrl`, `InvalidRequest` (Timeout/Invalid* reserved for Phase 4)
- `execute` — maps pure `Request` → njs fetch → `Result(Response, ClientError)`
- Response helpers: `is_success`, `is_client_error`, `is_server_error`, `is_redirect`, `status_text`

**`nginz_njs_http_client.gleam`** — njs entry point
- `demo` — returns stable request summary
- `fetch_demo` — real `ngx.fetch()` to another nginx location
- `request_demo` — full builder pipeline exercising headers, body, query params, auth, timeout

**Integration tests** — 3 scenarios with stock nginx, no native deps.

## Core abstractions

The architectural rule for this module: request construction and response interpretation stay pure; only `ngx.fetch()` execution touches nginx/njs runtime effects.

## Composition with other modules

`workflow/pipeline.gleam` consumes `http_client/fetch` as a building block — `fetch_step` delegates to `execute()` and maps all `ClientError` variants. This is the intended pattern: `http_client` owns execution; downstream modules own orchestration.

## Scripted core vs optional native integration

### Scripted core (all implemented)

- request construction, headers, body, query params
- auth/header shaping
- response classification
- builder pipeline pattern

### Future (Phase 4–5)

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

### Phase 4 — add policy wrappers around execution

- [ ] add typed retry policy values
- [ ] add timeout policy wrappers
- [ ] add auth/header injection helpers that compose with `Request`
- [ ] generate `Timeout`/`InvalidUrl`/`InvalidRequest` errors from wrappers

### Phase 5 — prepare for ecosystem reuse

- [ ] document patterns for use from `authz`, `webhook`, and future modules
- [ ] add examples showing pure request construction reused across multiple handlers
- [ ] consider JSON helpers, middleware-style composition

## TDD plan

- [x] unit-test request builders and pure model transformations (17 tests)
- [x] integration test for real `ngx.fetch()` path (3 scenarios)
- [ ] retries, timeouts, and higher-level policies behind their own test cases
- [x] integration tests distinguish stock-nginx behavior from native-backed scenarios

## Verification checklist

- [x] `bun scripts/test.js http_client` — 17 unit tests pass
- [x] `bun test modules/http_client/tests/basic/do.test.js` — 3 integration tests pass
- [x] `bun run test` — all 66 unit + 23 integration tests pass across all modules
