# nginz_njs_http_client

Typed `ngx.fetch()` wrapper for nginx written in Gleam — the highest-priority Tier 1 module.

## Use Case

**The problem**: your nginx layer needs to call another service, but raw fetch code quickly turns into repetitive glue for headers, tokens, timeouts, query strings, and error handling.

**How it solves it**: this module gives you one clean way to describe an outgoing HTTP call and then execute it. That keeps the request shape readable, predictable, and easy to reuse across different handlers instead of rebuilding the same fetch logic over and over. It starts simple, but it also gives the rest of the system a strong base to build on.

**When you would use this**: use it when nginx needs to talk to an auth service, profile service, internal API, or webhook target. It is the module that turns “we need to call something else first” into a normal, manageable building block.

## Design goals

- keep request construction pure and typed
- make auth headers, timeouts, method selection, and body first-class values
- keep nginx effects at the edge and core request shaping in Gleam
- the pure `Request` model is the stable input to all execution helpers

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.demo` | `js_content` | Returns a rendered demo request summary |
| `main.fetch_demo` | `js_content` | Real `ngx.fetch()` to a fixture upstream |
| `main.request_demo` | `js_content` | Full builder pipeline exercising headers, body, query params, auth, timeout |
| `main.middleware_demo` | `js_content` | Stacked middleware pipeline (bearer token, headers, content-type, timeout) |
| `main.retry_demo` | `js_content` | Fetch with retry policy (max 3 attempts) |

## nginx configuration

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8888;

        location /demo            { js_content main.demo; }
        location /fetch-demo      { js_content main.fetch_demo; }
        location /request-demo    { js_content main.request_demo; }
        location /middleware-demo { js_content main.middleware_demo; }
        location /retry-demo      { js_content main.retry_demo; }
    }
}
```

## Pure request model

`http_client/client.gleam` provides a typed `Request` value with:

- `method` — typed `Method` sum type (Get, Head, Post, Put, Patch, Delete, Options)
- `url` — target URL string
- `headers` — list of `(key, value)` pairs for arbitrary request headers
- `auth_header` — convenience field for typed auth injection (e.g., `"Bearer <token>"`)
- `body` — optional string body
- `query_params` — list of `(key, value)` pairs appended to the URL at fetch time
- `timeout_ms` — optional timeout hint

Builder helpers: `with_method`, `with_header`, `with_headers`, `with_bearer_token`, `with_body`, `with_query_param`, `with_query_params`, `with_timeout`.

`build_url` assembles the URL with query params. `summary` provides deterministic string rendering for testing.

## Runtime execution

`http_client/fetch.gleam` provides `execute(request)` → `Promise(Result(Response, ClientError))`:

- Converts the pure `Request` into an njs `Request`:
  - custom headers + auth header are merged into the runtime `Headers` object
  - optional body is converted to a `Buffer` via `from_string(body, Utf8)`
  - query params are appended to the URL
- Performs `ngx.fetch_request` and extracts `status` + `body` text
- Catches runtime failures and wraps them as `FetchFailed(reason)`

`Response` means the HTTP exchange completed and produced a response, even if the status is not 2xx.

## Error model

```gleam
pub type ClientError {
  FetchFailed(reason: String)      // transport/runtime failure in the fetch path
  Timeout(timeout_ms: Int)         // client-observed timeout
  InvalidUrl(url: String)          // malformed or unsupported URL
  InvalidRequest(reason: String)   // invalid request configuration
}
```

## Response helpers

```gleam
pub fn is_success(resp: Response) -> Bool        // 2xx
pub fn is_client_error(resp: Response) -> Bool   // 4xx
pub fn is_server_error(resp: Response) -> Bool   // 5xx
pub fn is_redirect(resp: Response) -> Bool       // 3xx
pub fn status_text(resp: Response) -> String     // e.g., "OK", "Not Found"
```

`http_client/response.gleam` provides body extraction helpers:

```gleam
body_or(response, "fallback")         // body if 2xx, else fallback
body_if_success(response)              // Ok(body) if 2xx, Error(body) otherwise
body_if_status(response, 201)          // Ok(body) if status matches
```

## Policy layer

`http_client/policy.gleam` provides retry composition around `execute()`:

```gleam
import http_client/policy.{Retry, execute_with_policy, new, with_retry}

let policy = new() |> with_retry(Retry(max_attempts: 3))
use result <- promise.await(execute_with_policy(req, policy))
```

- `RetryPolicy` — `NoRetry` or `Retry(max_attempts)`
- Immediate retry only (no backoff delay) — njs timer callbacks run outside request context and break `ngx.fetch()`
- `timeout_ms` is enforced by the execution layer via promise racing

## Middleware

`http_client/middleware.gleam` provides composable request transformation:

```gleam
import http_client/middleware.{add_header, bearer_token, json_content_type, stack, timeout_ms}

let mw = stack([
  bearer_token("my-token"),
  add_header("X-Request-Id", "req-001"),
  json_content_type(),
  timeout_ms(5000),
])

let req = new("https://api.example.test")
  |> middleware.apply(mw)
  |> client.with_method(Post)
```

- `Middleware` — pure `fn(Request) -> Request`
- `stack` — composes middlewares left-to-right
- Pre-built: `bearer_token`, `add_header`, `json_content_type`, `timeout_ms`

## Composition with other modules

`workflow/pipeline.gleam` consumes `http_client/fetch` as a Gleam building block — `fetch_step` delegates to `execute()` and maps all `ClientError` variants to `Failed(reason)` strings. Future modules (`authz`, `webhook`) should follow the same pattern: import `http_client/fetch` for execution, `http_client/client` for request building, and optionally `http_client/policy` for retry semantics.

## What is implemented (Phases 1–5 complete)

**`http_client/client.gleam`** — pure request model
- `Method` — 7 HTTP methods as a sum type (Get, Head, Post, Put, Patch, Delete, Options)
- `Request` — typed descriptor with headers, auth, body, query params, timeout
- 8 builder helpers
- `build_url`, `summary` — deterministic for testing

**`http_client/fetch.gleam`** — execution layer
- `Response(status: Int, body: String)` — typed HTTP response
- `ClientError` — `FetchFailed`, `Timeout`, `InvalidUrl`, `InvalidRequest`
- `execute` — maps pure `Request` → njs fetch → `Result(Response, ClientError)`
- Response helpers: `is_success`, `is_client_error`, `is_server_error`, `is_redirect`, `status_text`

**`http_client/policy.gleam`** — retry composition

**`http_client/middleware.gleam`** — composable request transformations

**`http_client/response.gleam`** — body extraction helpers

**`nginz_njs_http_client.gleam`** — njs entry point (5 handlers)

**Integration tests** — 8 scenarios with stock nginx, no native deps.

## Limitations

- only a text-response fetch path is implemented (no streaming or binary body access)
- retry is immediate-only (no backoff delay) — njs timer context restrictions prevent `ngx.fetch()` after `setTimeout`
- timeout is client-observed and does not abort an already in-flight upstream fetch
- no circuit breaker logic or connection pooling

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

### Phase 4 — add policy wrappers around execution ✅

- [x] add typed retry policy values (`RetryPolicy`, `Policy`)
- [x] add client-observed timeout enforcement in the execution layer
- [x] add composable middleware for auth/header injection
- [x] immediate retry with `execute_with_policy` (backoff delay blocked by njs timer context)

### Phase 5 — prepare for ecosystem reuse ✅

- [x] document patterns for use from `workflow`, `authz`, `webhook`, and future modules
- [x] add middleware-style composition (`Middleware`, `stack`)
- [x] add response body helpers (`body_or`, `body_if_success`, `body_if_status`)
- [x] examples showing pure request construction reused across multiple handlers

## Verification checklist

- [x] `bun scripts/test.js http_client` — 40 unit tests pass
- [x] `bun test modules/http_client/tests/basic/do.test.js` — 8 integration tests pass
- [x] `bun run test` — all 83 unit + 25 integration tests pass across all modules
