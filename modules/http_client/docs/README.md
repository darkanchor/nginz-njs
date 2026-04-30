# http_client

Typed `ngx.fetch()` wrapper. Substantial Phase 1–5 foundations are in place: an expanded pure request model, a typed fetch execution path with body support, response classification helpers, immediate retry policy wrappers, composable middleware, and response body helpers.

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
  Timeout(timeout_ms: Int)         // defined for future policy/validation layers
  InvalidUrl(url: String)          // defined for future policy/validation layers
  InvalidRequest(reason: String)   // defined for future policy/validation layers
}
```

Currently `execute()` only produces `FetchFailed`. `Timeout`, `InvalidUrl`, and `InvalidRequest` are already part of the public error model, but they are not yet emitted by `execute()` itself; they are reserved for future policy and validation layers.

## Response helpers

```gleam
pub fn is_success(resp: Response) -> Bool        // 2xx
pub fn is_client_error(resp: Response) -> Bool    // 4xx
pub fn is_server_error(resp: Response) -> Bool    // 5xx
pub fn is_redirect(resp: Response) -> Bool        // 3xx
pub fn status_text(resp: Response) -> String      // e.g., "OK", "Not Found"
```

## Composable with other modules

`workflow/pipeline.gleam` consumes `http_client/fetch` as a Gleam building block — `fetch_step` delegates to `execute()` and maps all `ClientError` variants to `Failed(reason)` strings. This is the intended composability pattern: `http_client` owns request execution; downstream modules own orchestration semantics.

## Policy layer

`http_client/policy.gleam` provides retry composition around `execute()`:

```gleam
import http_client/policy.{Retry, execute_with_policy, new, with_retry}

let policy = new() |> with_retry(Retry(max_attempts: 3))
use result <- promise.await(execute_with_policy(req, policy))
```

- `RetryPolicy` — `NoRetry` or `Retry(max_attempts)`
- `Policy` — wraps `RetryPolicy`; extensible for future options
- Immediate retry only (no backoff delay) — njs timer callbacks run outside request context and break `ngx.fetch()`
- `timeout_ms` is passed through to `ngx.fetch()` options; the distinct `Timeout` error variant is not yet emitted by `execute()`

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

## Response helpers

`http_client/response.gleam` provides body extraction helpers:

```gleam
import http_client/response.{body_if_status, body_if_success, body_or}

body_or(response, "fallback")            // body if 2xx, else fallback
body_if_success(response)                 // Ok(body) if 2xx, Error(body) otherwise
body_if_status(response, 201)             // Ok(body) if status matches
```

## Composable with other modules

`workflow/pipeline.gleam` consumes `http_client/fetch` as a Gleam building block — `fetch_step` delegates to `execute()` and maps all `ClientError` variants to `Failed(reason)` strings. Future modules (`authz`, `webhook`) should follow the same pattern: import `http_client/fetch` for execution, `http_client/client` for request building, and optionally `http_client/policy` for retry semantics.

## Limitations

- only a text-response fetch path is implemented (no streaming or binary body access)
- retry is immediate-only (no backoff delay) — njs timer context restrictions prevent `ngx.fetch()` after `setTimeout`
- `Timeout`, `InvalidUrl`, and `InvalidRequest` are part of the public error model, but `execute()` currently only produces `FetchFailed`
- no circuit breaker logic or connection pooling
- query param values are not URL-encoded
- `ngx.fetch()` is subject to njs async limitations inside certain nginx phases
- integration targets another nginx location rather than an external upstream process
- JSON body parsing requires `gleam_json` as an additional dependency (not yet added)

## Testing

```bash
# unit tests (34 tests — pure model, builders, response helpers, policy, middleware)
cd modules/http_client && gleam test

# integration tests (5 scenarios — demo, fetch_demo, request_demo, middleware_demo, retry_demo)
bun test modules/http_client/tests/basic/do.test.js
```
