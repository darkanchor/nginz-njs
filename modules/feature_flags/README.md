# nginz_njs_feature_flags

Feature flag evaluation with stable bucketing for A/B routing in nginx. Pure hash-based bucketing, no external process, deterministic per identity.

## Design goals

- Bucketing is a pure function of the identifier string — same input always maps to the same 0–99 bucket, no state required
- Three bucket key types out of the box: by request id, user id, or remote address — same flag, different targeting granularity
- Flag configuration is read from nginx variables, keeping the evaluation path fully in-process with no I/O
- `is_enabled` is a single boolean expression — easy to unit test exhaustively with known bucket values

## What is implemented

**`feature_flags/evaluation.gleam`**
- `Flag(name, enabled, rollout_pct)` — the flag descriptor
- `BucketKey` — `ByRequestId(id)` | `ByUserId(uid)` | `ByRemoteAddr(addr)`
- `bucket(key)` — FNV-1a 32-bit hash mod 100; stable, uniform, no collisions at test scale
- `is_enabled(flag, key)` — `flag.enabled && bucket(key) < rollout_pct`

**`nginz_njs_feature_flags.gleam`** (njs entry point)
- `evaluate` — reads `$ff_<name>_enabled` and `$ff_<name>_pct` nginx vars; returns `"1"` or `"0"`
- `bucket` — returns the raw bucket number for the resolved key; useful for debugging

Flag config is set via nginx `set` directives or mapped from an upstream source:
```nginx
set $ff_dark_mode_enabled 1;
set $ff_dark_mode_pct     25;
set $ff_key_type          user_id;
set $ff_key               $http_x_user_id;
```

**Integration tests**
- `tests/basic/` — sets vars inline, calls evaluate and bucket handlers, checks results

## Batched todos

### Batch 1 — flag configuration
- [ ] Add JSON flag config loading from a file (`njs/fs` readFileSync at startup) so you don't need one pair of nginx vars per flag
- [ ] Define a `FlagConfig` type: `Dict(String, Flag)` loaded once and reused per request
- [ ] Add `js_set`-based handler that sets a variable directly (more composable than a content handler)

### Batch 2 — targeting
- [ ] Add override support: force a flag on or off for a specific key (for internal users, QA, etc.)
- [ ] Add `ByHeader(name)` bucket key — target by arbitrary request header value
- [ ] Add `ByQueryParam(name)` bucket key

### Batch 3 — multi-variant flags
- [ ] Extend `Flag` to support variants: `Flag(name, variants: List(#(String, Int)))` where each variant has a name and a cumulative rollout percentage
- [ ] `evaluate_variant(flag, key) -> String` — returns the variant name instead of a boolean
- [ ] Integration test: three-way A/B/C split with stable assignment

### Batch 4 — shared-dict persistence (blocked on nginz)
- [ ] Once the nginz `shared_dict` native module lands: load flag config into shared memory at nginx startup
- [ ] Hot-reload: update flag config without nginx reload (write to shared dict via admin API location)
- [ ] Sticky overrides: persist per-user overrides in shared dict across requests

### Batch 5 — observability
- [ ] Emit `$ff_bucket` and `$ff_decision` as nginx variables for access log inclusion
- [ ] Add structured logging: flag name, bucket, decision, rollout_pct on each evaluation
- [ ] Integration test: verify log output contains expected fields

## Verification checklist

- [ ] `bun scripts/test.js feature_flags` — all 7 unit tests pass
- [ ] `bun test modules/feature_flags/tests/basic/do.test.js` — evaluate and bucket integration passes
- [ ] Manual: set `rollout_pct=50`, send 1000 requests with random user ids, verify ~50% get `"1"`
- [ ] Manual: set `rollout_pct=0`, verify all requests get `"0"` regardless of key
- [ ] Manual: set `rollout_pct=100`, verify all requests get `"1"` regardless of key
- [ ] Stability check: same user id returns same bucket across nginx restarts (pure hash, no seed)
