# mlcache

Two-level cache scaffold. Proves the package shape, reusable cache semantics model, and nginx integration surface. Uses the njs built-in `ngx.shared` for cross-request backing.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.describe` | `js_content` | Returns a stable summary of the scaffold cache config |

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
    }
}
```

## Composition model

`mlcache` should later be a reusable cache capability consumed by `authz`, `feature_flags`, `webhook`, and possibly `session`. Consumers should still own key design and invalidation meaning.

## Limitations

- no LRU/store adapter wired yet (the model declares `SharedDict` but the adapter is not yet implemented)
- no stampede-collapse lock yet

## Testing

```bash
# unit tests
cd modules/mlcache && gleam test

# integration tests
bun test modules/mlcache/tests/basic/do.test.js
```
