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
- `Override` — `NoOverride` | `ForceOn` | `ForceOff` (takes precedence over rollout)
- `bucket(key)` — FNV-1a 32-bit hash mod 100; stable, uniform
- `is_enabled(flag, key)` — `flag.enabled && bucket(key) < rollout_pct`
- `evaluate(flag, key, override)` — full evaluation with override precedence
- Pure config parsing: `parse_enabled`, `parse_rollout_pct`, `parse_override`

**`nginz_njs_feature_flags.gleam`** (njs entry point)
- `evaluate` — `js_content` handler for override-aware flag evaluation
- `evaluate_js_set` — `js_set`-compatible handler for routing decisions (use with `js_set $var main.evaluate_js_set`)
- `bucket` — returns the raw bucket number for the resolved key; useful for debugging

Flag config is set via nginx `set` directives or mapped from an upstream source:
```nginx
set $ff_dark_mode_enabled 1;
set $ff_dark_mode_pct     25;
set $ff_key_type          user_id;
set $ff_key               $http_x_user_id;
# Optional per-request override:
set $ff_dark_mode_override on;   # force on regardless of rollout
```

**Integration tests**
- `tests/basic/` — 7 scenarios: on/off, bucket determinism/range/distribution, force-on/force-off overrides

## Roadmap position

`feature_flags` is a Tier-1 foundation module in `ROADMAP.md`. It delivers real value with no native dependency: deterministic bucketing, explicit targeting, override precedence, config parsing helpers, and routing-friendly outputs via both `js_content` and `js_set` handlers.

Shared state or hot reload via `ngx.shared` is a later adapter layer, not the heart of the module.

## Core abstractions

- `Flag` — the pure flag descriptor used by the evaluator
- `BucketKey` — the stable identity used for assignment
- `bucket(key)` — deterministic bucket assignment
- `is_enabled(flag, key)` — the smallest boolean evaluation surface
- later: variant-aware flags, override types, and config lookup helpers

The evaluator should stay entirely side-effect free. Configuration lookup and request-to-key resolution belong at the nginx adapter boundary.

## Scripted core vs optional native integration

### Scripted core

- rollout evaluation
- targeting by request-local identity
- override precedence
- variant selection
- logging and routing-friendly outputs

### Optional native integration

- njs built-in `ngx.shared` for runtime-togglable flag state (no native nginz dependency needed)
- hot reload or sticky overrides backed by shared dict

The module is production-useful in pure scripted mode. `ngx.shared` improves dynamism, not defines the evaluation model.

Cross-module direction: when runtime-backed flag state arrives, `feature_flags` should prefer composing a reusable cache/state layer such as `mlcache` rather than absorbing cache policy directly into the evaluator.

## Phased implementation plan

### Phase 1 — formalize the config model ✅

Goal: make the pure evaluator reusable regardless of where configuration comes from.

- [x] keep nginx variable-driven config as the baseline contract
- [x] add pure config parsing helpers: `parse_enabled`, `parse_rollout_pct`, `parse_override`
- [x] add a `js_set`-compatible evaluation export (`evaluate_js_set` handler)
- [x] document the thin adapter pattern: resolve config → resolve key → evaluate

### Phase 2 — add richer targeting and overrides ✅

Goal: increase expressiveness without introducing shared state.

- [x] add key resolvers for header, query param, and explicit variable-derived identity (3 built-in: request_id, user_id, remote_addr)
- [x] add request-local force-on and force-off overrides (`Override` type, `$ff_<name>_override` nginx var)
- [x] define clear precedence: override > rollout percentage (enforced in `evaluate()`)
- [x] document how targeting stays deterministic even when request sources differ

### Phase 3 — add multi-variant evaluation ✅

Goal: make the module useful for real product rollout rather than only boolean gates.

- [x] introduce variant-capable flag types (`Variant`, `VariantConfig`, `VariantFlag`)
- [x] add `select_variant(flag, key, override)` with stable weight-based assignment
- [x] keep boolean evaluation as a thin specialization of the same bucketing model
- [x] add integration coverage for A/B/C style routing using nginx variables only

### Phase 4 — add observability and composition outputs ✅

Goal: make flag decisions easy to inspect and reuse across the nginx config.

- [x] emit decision metadata via `describe_boolean` and `describe_variant`
- [x] expose routing-friendly outputs via `variant` and `describe` handlers
- [x] document patterns where flag output feeds `workflow` or `authz` decisions

### Phase 5 — optional runtime state backends

Goal: improve operability later without disturbing the pure evaluator.

- [ ] optionally support startup-loaded file config once the variable-driven baseline is solid
- [ ] later support shared-state-backed config and sticky overrides when the native primitives are ready
- [ ] keep all backend choice behind the same pure evaluation API

## TDD plan

- [x] unit-test bucket determinism and rollout boundaries exhaustively (7 tests)
- [x] unit-test config parsing defaults and override precedence (14 tests)
- [x] unit-test variant selection, weight distribution, and fallback (8 tests)
- [x] unit-test variant config parsing (4 tests)
- [x] unit-test decision metadata output format (4 tests)
- [x] add `tests/basic/` coverage for overrides, variants, and describe handlers (5 new scenarios)
- [ ] add integration tests for `js_set` usage (handler exists, njs runtime behavior needs verification)
- [ ] isolate future shared-state adapters from the baseline deterministic evaluator tests

## Atomic commit strategy

- [x] `feature_flags: add config parsing helpers and js_set evaluation`
- [x] `feature_flags: add targeting and override primitives`
- [x] `feature_flags: add variant evaluation`
- [x] `feature_flags: add observability outputs`
- [ ] `docs: document feature flag composition patterns`

## Verification checklist

- [x] `bun scripts/test.js feature_flags` — 37 unit tests pass
- [x] `bun test modules/feature_flags/tests/basic/do.test.js` — 12 integration tests pass
- [x] Manual: set `rollout_pct=50`, send 1000 requests with random user ids, verify ~50% get `"1"`
- [x] Manual: set `rollout_pct=0`, verify all requests get `"0"` regardless of key
- [x] Manual: set `rollout_pct=100`, verify all requests get `"1"` regardless of key
- [x] Stability check: same user id returns same bucket across nginx restarts (pure hash, no seed)
- [x] Override check: `ForceOn` always returns `"1"`, `ForceOff` always returns `"0"`
- [x] Variant check: same key always maps to same variant (deterministic weight allocation)
- [x] Variant check: `ForceOn` overrides disabled flag, `ForceOff` forces fallback
- [x] Decision metadata: `describe` and `describe_variant` emit stable structured output
