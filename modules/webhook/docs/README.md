# webhook

Webhook protocol scaffold. This module currently proves the package shape, reusable webhook config model, and nginx integration surface for future outbound signing and inbound verification flows.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.describe_outbound` | `js_content` | Returns the outbound webhook scaffold summary |
| `main.describe_inbound` | `js_content` | Returns the inbound webhook scaffold summary |

## nginx configuration

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8888;

        location /describe-outbound {
            js_content main.describe_outbound;
        }

        location /describe-inbound {
            js_content main.describe_inbound;
        }
    }
}
```

## Composition model

`webhook` should later use `http_client` for outbound delivery and `response_transform` for payload shaping or normalization. The handler layer should stay thin and should not own transport or transform primitives directly.

## Limitations

- no real signing or verification yet
- no real outbound delivery yet
- no replay protection or cache integration yet

## Testing

```bash
# unit tests
cd modules/webhook && gleam test

# integration tests
bun test modules/webhook/tests/basic/do.test.js
```
