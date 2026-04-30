# mlcache

Two-level cache scaffold. This module currently proves the package shape, reusable cache semantics model, and nginx integration surface while making the `shared_dict` blocker explicit.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.describe` | `js_content` | Returns a stable summary of the scaffold cache config |
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

`mlcache` should later be a reusable cache capability consumed by `authz`, `feature_flags`, `webhook`, and possibly `session`. Consumers should still own key design and invalidation meaning.

## Limitations

- no real backing store yet
- no LRU/store implementation yet
- runtime shared state is intentionally blocked until `shared_dict` exists and its contract is stable

## Testing

```bash
# unit tests
cd modules/mlcache && gleam test

# integration tests
bun test modules/mlcache/tests/basic/do.test.js
```
