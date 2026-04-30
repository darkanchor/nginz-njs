# response_transform

Response transformation scaffold. This module currently proves the package shape, pure plan model, and nginx integration surface for a future body-shaping library.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.describe` | `js_content` | Returns a summary of the demo response-transform plan |
| `main.preview_plan` | `js_content` | Returns a stable preview string for the scaffold plan |

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

        location /preview-plan {
            js_content main.preview_plan;
        }
    }
}
```

## Composition model

`response_transform` should be used as a Gleam library first. `workflow` or `webhook` should build or choose a `Plan` and then hand it to a later execution adapter rather than duplicating transform behavior in their own handler layers.

## Limitations

- no real body-filter adapter yet
- no JSON parsing or path-based mutation yet
- no status/header-aware conditional transforms yet

## Testing

```bash
# unit tests
cd modules/response_transform && gleam test

# integration tests
bun test modules/response_transform/tests/basic/do.test.js
```
