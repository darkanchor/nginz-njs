# session

Session-state scaffold. This module currently proves the package shape, reusable session descriptor model, and nginx integration surface while making the `shared_dict` blocker explicit.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.describe` | `js_content` | Returns a stable summary of the scaffold session descriptor |
| `main.blocked` | `js_content` | Returns `501` with the shared-dict blocker message |

## nginx configuration

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8888;

        location /describe {
            js_content main.describe;
        }

        location /blocked {
            js_content main.blocked;
        }
    }
}
```

## Composition model

`session` should later provide reusable session facts that `authz` and `feature_flags` can consume. It should not become a catch-all policy layer for authorization or targeting.

## Limitations

- no real backing store yet
- no issuance, validation, or crypto implementation yet
- runtime storage is intentionally blocked until `shared_dict` exists and its contract is stable

## Testing

```bash
# unit tests
cd modules/session && gleam test

# integration tests
bun test modules/session/tests/basic/do.test.js
```
