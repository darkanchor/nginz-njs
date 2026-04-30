# nginz_njs_workflow

Subrequest orchestration and `ngx.fetch()`-driven enrichment pipelines for nginx. Parallel fan-out and sequential chaining, built on promises, fully composable.

## Design goals

- A `Step` is just `fn(HTTPRequest) -> Promise(StepResult)` — steps compose, map, and filter like any other values
- `run` dispatches all steps in parallel via `promise.await_list` — no sequential blocking unless you explicitly chain
- `StepResult` carries either `Fetched(status, body)` or `Failed(reason)` — errors are values, not exceptions
- Two backends: `subrequest_step` (nginx internal locations, same worker) and `fetch_step` (`ngx.fetch()`, external HTTP)
- The module handles orchestration; what you do with the results is up to the handler

## What is implemented

**`workflow/pipeline.gleam`**
- `StepResult` — `Fetched(status, body)` | `Failed(reason)`
- `Step` — type alias for the step function
- `run` — parallel dispatch via `promise.await_list`
- `subrequest_step(path)` — nginx internal subrequest
- `fetch_step(url)` — external HTTP via `ngx.fetch()`
- `map_result` — transform a `Fetched` result, pass through `Failed`
- `filter_ok` — extract `(status, body)` pairs, discard failures

**`nginz_njs_workflow.gleam`** (njs entry point)
- `enrich` — fans out to `/internal/auth` and `/internal/profile` in parallel; joins bodies with newline; returns 502 if either fails
- `chain` — single sequential subrequest to `/internal/upstream`; proxies status and body

**Integration tests**
- `tests/basic/` — chain handler with a plain echoed upstream, no native deps
- `tests/enrich/` — fan-out to native `echoz` backends, verifies JSON bodies combined (`make` required)

## Batched todos

### Batch 1 — sequential pipelines
- [ ] Add `run_sequential(r, steps)` — steps execute in order, each receives the previous result
- [ ] Add `and_then(step, f)` combinator — chains a step that depends on the prior result
- [ ] Integration test: enrich → transform → forward chain

### Batch 2 — step control
- [ ] Add timeout wrapper: `with_timeout(step, ms)` — returns `Failed("timeout")` if the step exceeds the limit
- [ ] Add retry wrapper: `with_retry(step, n)` — retries up to `n` times on `Failed`
- [ ] Add `map_body(step, f)` — convenience for transforming only the response body

### Batch 3 — request forwarding
- [ ] `subrequest_step` currently passes an empty options object — add method and body forwarding from the parent request
- [ ] `fetch_step` should propagate configurable headers from the parent request (Authorization, X-Request-Id, etc.)
- [ ] Add `fetch_step_with_opts(url, opts)` for full control over method, headers, body

### Batch 4 — result merging strategies
- [ ] Add `merge_json(results)` — parse each body as JSON, deep-merge into a single object
- [ ] Add `first_ok(results)` — return the first non-error result (for fallback chains)
- [ ] Add `require_all(results)` — fail fast if any step failed, returning 502

### Batch 5 — production hardening
- [ ] Structured error logging: log each `Failed(reason)` with the step path and request id
- [ ] Expose orchestration metadata as nginx variables (`$workflow_steps`, `$workflow_errors`)
- [ ] Integration test: timeout scenario, retry scenario

## Verification checklist

- [ ] `bun scripts/test.js workflow` — all 6 unit tests pass
- [ ] `bun test modules/workflow/tests/basic/do.test.js` — chain integration passes
- [ ] `bun test modules/workflow/tests/enrich/do.test.js` — fan-out integration passes (`make` required)
- [ ] Manual: enrich with a slow backend to verify promise parallelism (both steps should complete in ~max(t1,t2), not t1+t2)
- [ ] Manual: introduce a failing backend, verify 502 and logged reason
