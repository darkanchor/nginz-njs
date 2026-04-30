# nginz_njs_http_client

Typed HTTP client scaffold for nginx written in Gleam. The long-term goal is a composable wrapper over `ngx.fetch()`; the current module is intentionally small and establishes the package layout, pure request-building core, and runnable nginx test surface.

## Roadmap position

`http_client` is the highest-priority Tier 1 module in `ROADMAP.md`. It is the missing foundation that should make `workflow` and other upstream-calling modules more ergonomic without introducing any native dependency.

## Design goals

- keep request construction pure and typed
- make auth headers, timeouts, and method selection first-class values
- keep nginx effects at the edge and core request shaping in Gleam
- start with a scaffold that proves packaging, testing, and integration before real fetch execution work lands

## What is implemented

**`http_client/client.gleam`**
- `Method` — HTTP method sum type
- `Request` — typed request descriptor with auth header and timeout fields
- `new`, `with_method`, `with_bearer_token`, `with_timeout` — pure builder helpers
- `summary` — deterministic string rendering used by unit and integration tests

**`http_client/fetch.gleam`**
- `Response` and `ClientError` — typed runtime results for the first fetch milestone
- `execute` — maps a pure `Request` into a real `ngx.fetch_request` call and returns `Result(Response, ClientError)`

In this first milestone, HTTP status is part of `Response`; `ClientError` is reserved for failures in the fetch/runtime path itself.

**`nginz_njs_http_client.gleam`**
- `demo` — returns a stable rendered request summary through `js_content`
- `fetch_demo` — performs a real fetch to another nginx location and returns the upstream body

**Integration tests**
- `tests/basic/` — verifies both the pure scaffold handler and the first real fetch path with stock nginx only

## Core abstractions

- `Method` — request method as a sum type, not an arbitrary string
- `Request` — the pure request descriptor that should become the stable input to all future execution helpers
- request builder helpers such as `with_method`, `with_bearer_token`, and `with_timeout`
- future `Response` and `ClientError` types — these should be values returned from the effectful edge, not ad-hoc strings or exceptions in the core

The architectural rule for this module is: request construction and response interpretation should stay pure; only the actual `ngx.fetch()` execution path should touch nginx/njs runtime effects.

## Scripted core vs optional native integration

### Scripted core

- request construction
- auth/header shaping
- timeout and retry policy modeling
- response parsing and error classification
- composition helpers used by `workflow` and future modules

### Optional native integration

- none required for the baseline module
- future native integrations, if ever needed, should remain optional accelerators or capability providers rather than the main architecture

This module should be valuable before any native dependency exists. Its role is to make the built-in njs fetch surface composable from Gleam.

## Phased implementation plan

### Phase 1 — stabilize the pure request model

Goal: define the smallest useful request-building API before introducing runtime execution.

- [ ] expand `Request` to model headers, optional body, and query parameters explicitly
- [ ] keep method, timeout, and auth configuration as typed fields rather than stringly nginx glue
- [ ] add pure helpers for common auth/header patterns without coupling them to `ngx.fetch()` directly
- [ ] keep deterministic rendering/debug helpers so the core remains easy to test

### Phase 2 — add the first real `ngx.fetch()` adapter

Goal: prove one minimal execution path from pure `Request` to a typed response value.

- [ ] add a `Response` type with status, body, and a minimal header representation
- [ ] add a small execution function that maps `Request` into `ngx.fetch()` input and returns `Result(Response, ClientError)`
- [ ] keep the first execution milestone intentionally narrow: no retry logic, no advanced policy, no hidden defaults
- [ ] add one demo handler that performs a real fetch only once the execution contract is stable

### Phase 3 — add typed error and response shaping

Goal: turn fetch behavior into composable values rather than opaque runtime failure.

- [ ] define `ClientError` cases for timeout, transport failure, invalid response, and configuration errors
- [ ] add response helpers for body access, status checks, and common content-type-driven decoding paths
- [ ] keep parsing and classification logic separate from request execution
- [ ] document how this layer should feed `workflow` without duplicating orchestration concerns

### Phase 4 — add policy wrappers around execution

Goal: make the client pleasant to use in higher-level modules while preserving a small kernel.

- [ ] add typed retry policy values rather than ad-hoc retry booleans
- [ ] add timeout policy wrappers around the execution function
- [ ] add auth/header injection helpers that compose with the pure `Request` model
- [ ] keep wrappers layered on top of the core execution contract, not baked into it

### Phase 5 — prepare for ecosystem reuse

Goal: make `http_client` the reusable foundation the roadmap expects.

- [ ] document patterns for use from `workflow`, `authz`, and future enrichment modules
- [ ] document patterns for use from `workflow`, `authz`, `webhook`, and future enrichment modules
- [ ] keep public types small and stable before expanding feature surface
- [ ] add examples showing pure request construction reused across multiple handlers
- [ ] only then consider richer features such as JSON helpers, middleware-style composition, or runtime configuration loading

## TDD plan

- [ ] unit-test request builders and pure model transformations first
- [ ] add focused unit coverage for response and error types before wiring runtime execution
- [ ] add a narrow basic integration test for the first real `ngx.fetch()` path once Phase 2 starts
- [ ] keep retries, timeouts, and higher-level policies behind their own isolated test cases
- [ ] ensure integration tests continue to distinguish stock-nginx scaffold behavior from later native-backed or feature-heavy scenarios

## Atomic commit strategy

- [ ] `http_client: expand the pure request model`
- [ ] `http_client: add minimal typed fetch execution`
- [ ] `http_client: add response and error modeling`
- [ ] `http_client: add retry timeout and auth policy wrappers`
- [ ] `docs: document http_client usage patterns and roadmap alignment`

## Verification checklist

- [ ] `bun scripts/test.js http_client` — unit tests pass
- [ ] `bun test modules/http_client/tests/basic/do.test.js` — basic integration passes
