# authz

Policy-based HTTP authorization module. Provides composable, type-safe authorization rules that evaluate a `Context` (method, path, headers, JWT claims) and return `Allow` or `Deny`.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.check` | `js_content` | Evaluates default method + path rules; returns 204 or 403 |
| `main.jwt_check` | `js_content` | Reads `$jwt_claim_role` and checks against allowed roles |

## nginx configuration

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8888;

        location /api/ {
            js_content main.check;
        }

        location /admin/ {
            # requires nginz jwt module to populate $jwt_claim_role
            js_content main.jwt_check;
        }
    }
}
```

## Policy model

Rules are functions `fn(Context) -> Decision`. Combine them with `all_of`, `any_of`, and `not_`:

```gleam
import authz/policy.{all_of, any_of, has_claim, method_in, path_prefix}

let api_policy = all_of([
  method_in(["GET", "POST"]),
  path_prefix("/api"),
  any_of([has_claim("role", "admin"), has_claim("role", "user")]),
])
```

`evaluate(ctx, rules)` short-circuits on the first `Deny`.

## Limitations

- `jwt_check` depends on `$jwt_claim_role` being populated by the nginz native JWT module. The JWT signature is verified by the native layer, not here.
- No runtime policy reload. Policy rules are compiled into the njs bundle. Hot-reload requires an nginx restart or reload.
- Claims are read as single-value strings. Multi-value claims (e.g., comma-separated roles) require custom extraction logic.

## Testing

```bash
# unit tests (pure Gleam, no nginx required)
cd modules/authz && gleam test

# integration tests (requires built nginx binary)
bun test modules/authz/tests
```
