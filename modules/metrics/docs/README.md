# metrics

Metrics forwarding scaffold. This module currently proves the package shape, pure metric/event model, and nginx integration surface for future StatsD/DogStatsD emission.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.describe` | `js_content` | Returns a summary of the demo metric |
| `main.emit_demo` | `js_content` | Returns a deterministic rendered StatsD-style line |

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

        location /emit-demo {
            js_content main.emit_demo;
        }
    }
}
```

## Composition model

Other modules should later emit structured metric values into this library surface rather than formatting sink-specific protocol lines themselves.

## Limitations

- no real transport/emission yet
- no batching or sink configuration yet
- no log-phase hook wiring yet

## Testing

```bash
# unit tests
cd modules/metrics && gleam test

# integration tests
bun test modules/metrics/tests/basic/do.test.js
```
