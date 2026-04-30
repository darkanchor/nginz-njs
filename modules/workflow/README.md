# nginz_njs_workflow

Subrequest orchestration and `ngx.fetch()`-driven enrichment pipelines for nginx. Parallel fan-out and sequential chaining, built on promises, fully composable.

## Design goals

- A `Step` is just `fn(HTTPRequest) -> Promise(StepResult)` — steps compose, map, and filter like any other values
- `run` dispatches all steps in parallel via `promise.await_list` — no sequential blocking unless you explicitly chain
- `StepResult` carries either `Fetched(status, body)` or `Failed(reason)` — errors are values, not exceptions
- Two backends: `subrequest_step` (nginx internal locations, same worker) and `fetch_step` (`http_client` over `ngx.fetch()`, external HTTP)
- The module handles orchestration; what you do with the results is up to the handler

## What is implemented

**`workflow/pipeline.gleam`**
- `StepResult` — `Fetched(status, body)` | `Failed(reason)`
- `Step` — type alias for the step function
- `run` — parallel dispatch via `promise.await_list`
- `subrequest_step(path)` — nginx internal subrequest
- `fetch_step(url)` — external HTTP delegated through `http_client`
- `map_result` — transform a `Fetched` result, pass through `Failed`
- `filter_ok` — extract `(status, body)` pairs, discard failures

**`nginz_njs_workflow.gleam`** (njs entry point)
- `enrich` — fans out to `/internal/auth` and `/internal/profile` in parallel; joins bodies with newline; returns 502 if either fails
- `chain` — single sequential subrequest to `/internal/upstream`; proxies status and body
- `fetch_chain` — fetches another nginx location through `http_client` to demonstrate cross-module composition

**Integration tests**
- `tests/basic/` — chain handler with a plain echoed upstream, no native deps
- `tests/enrich/` — fan-out to native `echoz` backends, verifies JSON bodies combined (`make` required)

## Roadmap position

`workflow` is one of the highest-value Sprint 1 modules in this repo. It is the scripted composition layer that makes the rest of the system more useful, especially once a reusable `http_client` lands.

That is no longer just a roadmap statement: `workflow` now uses `http_client` directly for its external fetch path, which is the intended module relationship across this repo.

That means the implementation plan should prioritize a clean pipeline algebra first, not a pile of special-case handlers.

## Core abstractions

- `Step = fn(HTTPRequest) -> Promise(StepResult)` — the current step shape, kept small and composable
- `StepResult` — explicit success or failure values
- runners for parallel and sequential execution
- wrappers such as timeout, retry, recover, and mapping combinators
- merge and fallback combinators over collections of `StepResult`

The module should treat orchestration as the product and nginx subrequests/fetches as execution backends.

## Scripted core vs optional native integration

### Scripted core

- subrequest orchestration
- `ngx.fetch()` composition
- retries, timeouts, fallback behavior, and response merging
- enrichment logic and request forwarding policy

### Optional native integration

- `echoz` or other native modules behind internal locations for demos and integration proofs
- request id, shared state, or upstream primitives when they help real workflows

Native modules are useful here to showcase the hybrid model, but the workflow API itself should stay valid when every step is just an internal location or external HTTP call.

Ownership boundary: `http_client` owns HTTP execution and client-side failure details; `workflow` owns how those results are mapped into `StepResult` and composed into pipelines.

Cross-module direction: response/body shaping should later compose `response_transform`, and emitted pipeline instrumentation should later compose `metrics`, rather than being built directly into the step algebra.

## Phased implementation plan

### Phase 1 — complete the pipeline algebra

Goal: make sequencing and transformation first-class instead of burying them in handlers.

- [ ] split the current `run` semantics into explicit `run_parallel` and `run_sequential`
- [ ] add `and_then(step, f)` for dependent chaining
- [ ] add `map_body`, `map_result`, and `map_error` style combinators
- [ ] add a worked example for enrich → transform → forward

### Phase 2 — add operational control wrappers

Goal: model common production behavior as composable wrappers, not one-off handler logic.

- [ ] add `with_timeout(step, ms)`
- [ ] add `with_retry(step, n)`
- [ ] add `recover(step, fallback)` and `first_ok(results)`
- [ ] keep failure handling value-based rather than exception-based

### Phase 3 — support real request forwarding

Goal: make steps useful as general orchestration units instead of read-only demos.

- [ ] forward method and body through `subrequest_step`
- [ ] forward selected headers such as `Authorization` and `X-Request-Id`
- [ ] add `fetch_step_with_opts(url, opts)` while preserving `fetch_step(url)` as the smallest API
- [ ] document what is forwarded automatically versus explicitly configured

### Phase 4 — add merge strategies and production ergonomics

Goal: make the core pipeline reusable for aggregation, fallback, and enrichment flows.

- [ ] add `merge_json(results)` or equivalent structured merge helper
- [ ] add `require_all(results)` and `select_first_ok(results)`
- [ ] expose workflow metadata that can be logged or routed on
- [ ] document recipes for fan-out aggregation, fallback chains, and edge enrichment

### Phase 5 — align with the broader repo roadmap

Goal: keep `workflow` ready to compose with the next high-value modules rather than closing over today's demos.

- [ ] keep the API compatible with a future `http_client` wrapper
- [ ] treat native backends as optional capability providers, not required step types
- [ ] leave room for future shared-state caching without coupling it into the core step algebra

## TDD plan

- [ ] add unit tests for execution ordering and short-circuit behavior
- [ ] add unit tests proving parallel execution preserves all results
- [ ] add unit tests for retry, timeout, and recovery wrappers
- [ ] add `tests/basic/` scenarios for sequential and parallel composition without native dependencies
- [ ] keep `tests/enrich/` as optional hybrid-model proof using native modules behind internal locations

## Atomic commit strategy

- [ ] `workflow: add sequential runner and chaining combinators`
- [ ] `workflow: add timeout retry and recovery wrappers`
- [ ] `workflow: add explicit request forwarding options`
- [ ] `workflow: add merge and fallback combinators`
- [ ] `docs: document workflow recipes and roadmap alignment`

## Verification checklist

- [ ] `bun scripts/test.js workflow` — all 6 unit tests pass
- [ ] `bun test modules/workflow/tests/basic/do.test.js` — chain integration passes
- [ ] `bun test modules/workflow/tests/enrich/do.test.js` — fan-out integration passes (`make` required)
- [ ] Manual: enrich with a slow backend to verify promise parallelism (both steps should complete in ~max(t1,t2), not t1+t2)
- [ ] Manual: introduce a failing backend, verify 502 and logged reason
