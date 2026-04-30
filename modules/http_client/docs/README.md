# http_client

Typed `ngx.fetch()` wrapper scaffold. This module now proves both the pure request-building core and one real fetch execution path against another nginx location.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.demo` | `js_content` | Returns a rendered demo request summary from the pure client scaffold |
| `main.fetch_demo` | `js_content` | Performs a real `ngx.fetch()` call to a fixture upstream location and returns its body |

## nginx configuration

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8888;

        location /demo {
            js_content main.demo;
        }

        location /fetch-demo {
            js_content main.fetch_demo;
        }
    }
}
```

## Pure request model

The scaffold starts with a pure `Request` value and builder helpers such as `with_method`, `with_bearer_token`, and `with_timeout`. The first runtime milestone adds a separate effectful fetch adapter around this stable core instead of pushing `ngx.fetch()` details into the request-building logic.

## Runtime execution

`http_client/fetch.gleam` now provides a minimal `execute` function that converts the pure `Request` into an njs `Request`, performs `ngx.fetch_request`, and returns a typed `Result(Response, ClientError)`.

- `Response` means the HTTP exchange completed and produced a response, even if the status is not 2xx.
- `ClientError` is reserved for transport/runtime failure in the fetch path itself.

## Limitations

- only a narrow text-response fetch path is implemented
- no retry policy or timeout enforcement yet
- no general header dictionary or request body modeling yet
- integration currently targets another nginx location rather than an external upstream process
- `main.fetch_demo` is a demo handler proving the runtime seam, not the long-term public API shape

## Testing

```bash
# unit tests
cd modules/http_client && gleam test

# integration tests
bun test modules/http_client/tests/basic/do.test.js
```
