# session

Session-state scaffold. Proves the package shape, reusable session descriptor model, and nginx integration surface. Uses the njs built-in `ngx.shared` for server-side storage.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.describe` | `js_content` | Returns a stable summary of the scaffold session descriptor |

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

`session` should later provide reusable session facts that `authz` and `feature_flags` can consume. It should not become a catch-all policy layer for authorization or targeting.

## Limitations

- no real backing store wired yet (the model declares `SharedDict` but the adapter is not yet implemented)
- no issuance, validation, or crypto implementation yet

## Testing

```bash
# unit tests
cd modules/session && gleam test

# integration tests
bun test modules/session/tests/basic/do.test.js
```
