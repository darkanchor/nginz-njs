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

## Roadmap position

`feature_flags` is a first-priority foundation module. It should deliver real value with no native dependency at all: deterministic bucketing, explicit targeting, and routing-friendly outputs.

Anything involving shared state or hot reload is a later adapter layer, not the heart of the module.

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

- future shared runtime state once a native shared store exists
- hot reload or sticky overrides backed by native state primitives

The module should be production-useful in pure scripted mode first. Native state should improve ergonomics or dynamism, not define the evaluation model.

Cross-module direction: when runtime-backed flag state arrives, `feature_flags` should prefer composing a reusable cache/state layer such as `mlcache` rather than absorbing cache policy directly into the evaluator.

## Phased implementation plan

### Phase 1 — formalize the config model

Goal: make the pure evaluator reusable regardless of where configuration comes from.

- [ ] keep nginx variable-driven config as the baseline contract
- [ ] add a pure `FlagConfig` lookup model and parsing helpers
- [ ] add a `js_set`-friendly evaluation export so flags can feed routing directly
- [ ] document the thin adapter pattern: resolve config → resolve key → evaluate

### Phase 2 — add richer targeting and overrides

Goal: increase expressiveness without introducing shared state.

- [ ] add key resolvers for header, query param, and explicit variable-derived identity
- [ ] add request-local force-on and force-off overrides
- [ ] define clear precedence between overrides and rollout percentages
- [ ] document how targeting stays deterministic even when request sources differ

### Phase 3 — add multi-variant evaluation

Goal: make the module useful for real product rollout rather than only boolean gates.

- [ ] introduce variant-capable flag types
- [ ] add `evaluate_variant(flag, key)` with stable assignment semantics
- [ ] keep boolean evaluation as a thin specialization of the same bucketing model
- [ ] add integration coverage for A/B/C style routing using nginx variables only

### Phase 4 — add observability and composition outputs

Goal: make flag decisions easy to inspect and reuse across the nginx config.

- [ ] emit decision metadata such as flag name, bucket, and variant for logging
- [ ] expose routing-friendly outputs via `js_set` or equivalent handlers
- [ ] document patterns where flag output feeds `workflow` or `authz` decisions

### Phase 5 — optional runtime state backends

Goal: improve operability later without disturbing the pure evaluator.

- [ ] optionally support startup-loaded file config once the variable-driven baseline is solid
- [ ] later support shared-state-backed config and sticky overrides when the native primitives are ready
- [ ] keep all backend choice behind the same pure evaluation API

## TDD plan

- [ ] unit-test bucket determinism and rollout boundaries exhaustively
- [ ] unit-test config parsing defaults and override precedence
- [ ] add `tests/basic/` coverage for both `js_content` and `js_set` usage
- [ ] add integration tests for header/query-based targeting
- [ ] isolate future shared-state adapters from the baseline deterministic evaluator tests

## Atomic commit strategy

- [ ] `feature_flags: add config lookup model and js_set evaluation`
- [ ] `feature_flags: add targeting and override primitives`
- [ ] `feature_flags: add variant evaluation`
- [ ] `feature_flags: add observability outputs`
- [ ] `docs: document feature flag composition patterns and optional state backends`

## Verification checklist

- [ ] `bun scripts/test.js feature_flags` — all 7 unit tests pass
- [ ] `bun test modules/feature_flags/tests/basic/do.test.js` — evaluate and bucket integration passes
- [ ] Manual: set `rollout_pct=50`, send 1000 requests with random user ids, verify ~50% get `"1"`
- [ ] Manual: set `rollout_pct=0`, verify all requests get `"0"` regardless of key
- [ ] Manual: set `rollout_pct=100`, verify all requests get `"1"` regardless of key
- [ ] Stability check: same user id returns same bucket across nginx restarts (pure hash, no seed)
