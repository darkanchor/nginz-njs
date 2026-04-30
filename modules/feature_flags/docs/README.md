# feature_flags

Feature flag evaluation with stable bucketing for A/B routing. Flags are configured via nginx variables; bucket assignment is deterministic by a chosen key (request ID, user ID, or remote address).

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.evaluate` | `js_content` | Returns `"1"` (enabled) or `"0"` (disabled) for the named flag |
| `main.bucket` | `js_content` | Returns the stable bucket number (0–99) for the resolved key |

## nginx variables

| Variable | Purpose | Example |
|---|---|---|
| `$ff_name` | Flag name to evaluate | `"dark_mode"` |
| `$ff_key_type` | How to bucket: `request_id`, `user_id`, `remote_addr` | `"user_id"` |
| `$ff_key` | Key value for bucketing | `$upstream_http_x_user_id` |
| `$ff_<name>_enabled` | `"1"` = flag is active, `"0"` = always off | `"1"` |
| `$ff_<name>_pct` | Rollout percentage (0–100) | `"50"` |

## nginx configuration

```nginx
js_var $ff_dark_mode_enabled "1";
js_var $ff_dark_mode_pct     "25";

location /feature/dark-mode {
    set $ff_name     "dark_mode";
    set $ff_key_type "user_id";
    set $ff_key      $upstream_http_x_user_id;
    js_content main.evaluate;
}
```

Typical use: call `main.evaluate` from `js_set` to produce an nginx variable, then use that variable in routing decisions:

```nginx
js_set $dark_mode_enabled main.evaluate;

location / {
    if ($dark_mode_enabled = "1") {
        proxy_pass http://dark-mode-upstream;
    }
    proxy_pass http://default-upstream;
}
```

## Bucketing algorithm

Uses FNV-1a hash of the key string, modulo 100. Buckets are stable: the same key always maps to the same bucket. Rollout percentage `p` means all keys with `bucket(key) < p` are enabled.

## Limitations

- Flag configuration is static per nginx reload. For runtime flag changes without reload, store flag state in the njs built-in `ngx.shared` dict and read it from the handler.
- Bucket distribution assumes the key space is well-distributed (UUIDs, random request IDs). Sequential IDs may cluster.
- No flag dependency evaluation. Flags are evaluated independently.
- Once shared state exists, runtime-backed lookup should ideally compose a reusable cache/state module such as `mlcache` rather than embedding cache policy directly into `feature_flags`.

## Testing

```bash
# unit tests
cd modules/feature_flags && gleam test

# integration tests
bun test modules/feature_flags/tests
```
