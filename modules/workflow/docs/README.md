# workflow

Subrequest orchestration and `http_client`-driven enrichment pipelines. Composes async steps — subrequests to internal locations or external fetches — into declarative pipelines.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.enrich` | `js_content` | Fan-out: calls `/internal/auth` and `/internal/profile` in parallel |
| `main.chain` | `js_content` | Sequential: calls `/internal/upstream` and proxies its response |
| `main.fetch_chain` | `js_content` | Fetches another nginx location through the reusable `http_client` module |

## Pipeline model

A `Step` is `fn(HTTPRequest) -> Promise(StepResult)`. Compose steps with `run`:

```gleam
import workflow/pipeline.{run, subrequest_step, fetch_step}

let steps = [
  subrequest_step("/internal/auth"),
  subrequest_step("/internal/profile"),
]

use results <- promise.await(run(r, steps))
```

`run` executes all steps concurrently. `filter_ok` keeps only the successful ones. For sequential execution, use `promise.await` to chain steps manually.

`fetch_step` is intentionally not a raw `ngx.fetch()` wrapper owned by `workflow`. It delegates to the reusable `http_client` Gleam module, which is the intended building-block pattern for this repo.

Ownership boundary: `http_client` owns request execution and client-level failures; `workflow` owns step-level mapping and orchestration semantics.

Likewise, later body shaping should compose `response_transform`, and later instrumentation should compose `metrics`, instead of being reimplemented inside `workflow`.

## nginx configuration

```nginx
location /enrich {
    js_content main.enrich;
}

# Internal locations for subrequests
location /internal/auth {
    internal;
    proxy_pass http://auth-service;
}

location /internal/profile {
    internal;
    proxy_pass http://profile-service;
}
```

## Limitations

- `enrich` uses a fixed set of subrequests. To make the step list configurable at runtime, pass step paths via nginx variables and read them in the handler.
- `fetch_step` uses `ngx.fetch()` which is subject to njs's async limitations inside certain nginx phases.
- Results are concatenated as raw text. JSON merging requires a custom combiner.

## Testing

```bash
# unit tests
cd modules/workflow && gleam test

# integration tests
bun test modules/workflow/tests
```
