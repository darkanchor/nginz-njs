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
- `run_parallel` and `run` — parallel dispatch via `promise.await_list`
- `run_sequential` — ordered execution with optional short-circuiting on failure
- `and_then` — dependent step chaining against the previous `StepResult`
- `subrequest_step(path)` — nginx internal subrequest
- `fetch_step(url)` — external HTTP delegated through `http_client`
- `fetch_step_with_opts(build)` — external HTTP with full request builder control
- `map_result`, `map_body`, `map_error` — transform result, body, or failure reason
- `with_timeout`, `with_retry`, `recover` — operational wrappers over steps
- `first_ok`, `all_success`, `partition`, `summary` — collection helpers over step results
- `map_step`, `fail_on_status` — step-level adaptation helpers
- `filter_ok` — extract `(status, body)` pairs, discard failures

**`workflow/merge.gleam`**
- `merge_bodies(results, delimiter)` — join successful bodies into one response
- `merge_with(results, combiner)` — custom merge strategy over successful results
- `merge_headers(results, extract)` — placeholder hook for future header-aware forwarding
- `require_all(results)` — require every step to succeed
- `select_first_ok(results, default)` — choose the first success or a fallback

**`nginz_njs_workflow.gleam`** (njs entry point)
- `enrich` — fans out to `/internal/auth` and `/internal/profile` in parallel; joins bodies with newline; returns 502 if either fails
- `chain` — single sequential subrequest to `/internal/upstream`; proxies status and body
- `fetch_chain` — fetches another nginx location through `http_client` to demonstrate cross-module composition
- `sequential` — runs two subrequests in order and merges the bodies
- `retry` — demonstrates retry wrapper behavior
- `timeout` — demonstrates timeout wrapper behavior
- `recover_demo` — demonstrates failure recovery with a fallback body
- `first_ok_demo` — returns the first successful upstream response
- `map_body_demo` — transforms an upstream response body
- `summary` — returns aggregate success/failure counts for a workflow run

**Integration tests**
- `tests/basic/` — 9 scenarios covering chain, fetch_chain, sequential, retry, timeout, recovery, first_ok, body mapping, and summary without native deps
- `tests/enrich/` — 2 fan-out scenarios against native `echoz` backends (`make` required)

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

Cross-module direction: response/body shaping may later compose `response_transform`, and emitted pipeline instrumentation may later compose `metrics`, rather than being built directly into the step algebra. Those integrations are ecosystem follow-ons, not blockers to workflow completeness.

## Completion scope

`workflow` is complete for its current contract as a reusable orchestration layer:

- parallel and sequential step execution
- subrequest and `http_client` backends
- timeout, retry, and recovery wrappers
- result mapping/filtering helpers
- merge/fallback combinators
- nginx handlers and integration scenarios demonstrating those behaviors

Future integrations such as `response_transform`, `metrics`, or shared-state caching are intentionally outside the current completion bar.

## Future consolidation track

Milestone 2 no longer treats circuit-aware behavior as a sibling package. The useful part of that design belongs here because `workflow` already owns retry, recovery, fallback, and orchestration semantics.

### Phase 4 — add circuit-aware resilience composition

Goal: absorb the real value of the old circuit-breaker wrapper design without turning one native variable into a separate top-level module.

- [ ] `workflow/circuit` helpers that read `$ngz_circuit_state` into a typed circuit fact
- [ ] step wrappers such as `skip_when_open`, `allow_probe_when_half_open`, and `recover_when_open`
- [ ] degraded-mode orchestration helpers that choose cached/static fallback data instead of hard-coded standalone 503 pages
- [ ] retry-suppression helpers so open circuits do not combine with blind retries
- [ ] response shaping only through existing merge/composition surfaces or `response_transform`, not bespoke fallback-page ownership inside `workflow`

## TDD plan

- [x] unit-test `StepResult` variants, mapping/filtering helpers, and collection combinators
- [x] unit-test merge/fallback behavior (`merge_bodies`, `merge_with`, `require_all`, `select_first_ok`)
- [x] type-check wrapper surfaces for retry, timeout, and recovery composition
- [x] `tests/basic/` scenarios for sequential/parallel orchestration without native dependencies
- [x] `tests/enrich/` as optional hybrid-model proof using native modules behind internal locations
- [ ] unit-test circuit-state parsing and circuit-aware wrapper behavior
- [ ] integration-test open / half-open / closed orchestration against native circuit variables
- [ ] integration-test degraded fallback selection without coupling to standalone 503 page adapters

## Verification checklist

- [x] `bun scripts/test.js workflow` — 33 unit tests pass
- [x] `bun test modules/workflow/tests/basic/do.test.js` — 9 basic integration tests pass
- [x] `bun test modules/workflow/tests/enrich/do.test.js` — 2 fan-out integration tests pass (`make` required)
- [ ] `bun test modules/workflow/tests/circuit/do.test.js` — circuit-aware orchestration passes (`make` required)
