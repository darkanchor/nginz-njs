# nginz_njs_mlcache

Two-level cache scaffold for nginx written in Gleam. The long-term goal is a reusable cache capability that other modules can compose for runtime lookups, while keeping domain-specific key and invalidation policy outside the cache primitive itself.

## Roadmap position

`mlcache` is a Tier-2 module in `ROADMAP.md` and is blocked on the native `shared_dict` primitive for a stable cross-request/shared backing store. The scaffold therefore focuses on reusable cache semantics and explicit blocker behavior rather than pretending the runtime backing already exists.

## Design goals

- model cache semantics as reusable values first
- separate cache policy from consumer-domain concerns
- let `authz`, `feature_flags`, `webhook`, and `session` compose cache behavior rather than embedding bespoke caching
- keep shared-state/runtime backing out of the scaffold phase

## What is implemented

**`mlcache/model.gleam`**
- `Backend`, `RefreshPolicy`, `CacheConfig`, and `LookupResult`
- `default_config`, `summary`, and `blocked_message`

**`nginz_njs_mlcache.gleam`**
- `describe` — returns a stable summary of the scaffold cache config
- `blocked` — returns `501` with the shared-dict blocker message

**Integration tests**
- `tests/basic/` — verifies both the descriptive scaffold path and explicit blocker behavior with stock nginx only

## Core abstractions

- `CacheConfig` — reusable cache configuration contract
- `Backend` — backing strategy as a value, not hidden mutable state
- `RefreshPolicy` — refresh semantics owned by the cache primitive rather than by consumers individually

The architectural rule for this module is: `mlcache` should expose reusable cache semantics, while consumers continue to own domain-specific keying and invalidation meaning.

## Cross-module composition boundary

- `authz` should later compose `mlcache` for remote-decision or introspection caching
- `feature_flags` should later compose `mlcache` for runtime-backed flag state lookup
- `webhook` may later use `mlcache` for replay/idempotency support
- `session` may later use `mlcache`-like lookup semantics, but should continue owning session policy rather than becoming a general cache façade

## Scripted core vs optional native integration

### Scripted core

- cache config and refresh semantics
- fetch-on-miss modeling
- reusable cache-policy helpers

### Optional native integration

- future `shared_dict` backing once the native primitive exists and is stable
- optional external backing stores if required later

## Phased implementation plan

### Phase 1 — stabilize the cache semantics model

Goal: define reusable cache contracts before runtime backing exists.

- [ ] expand config with TTL, stale, and refresh controls
- [ ] keep summary and debug semantics deterministic and testable
- [ ] add validation for conflicting cache settings

### Phase 2 — add pure fetch-on-miss helpers

Goal: support future consumers without coupling to a runtime store yet.

- [ ] define lookup result transitions and refresh flow helpers
- [ ] document how consumer modules should own keys and invalidation semantics
- [ ] keep cache policy reusable and domain-agnostic

### Phase 3 — add backing-store adapters

Goal: connect the reusable cache model to shared state once the platform is ready.

- [ ] add the first shared-dict-backed adapter when the native primitive lands
- [ ] add stampede-collapse behavior only after the runtime contract is stable
- [ ] keep backing-store failure separate from cache semantics

## TDD plan

- [ ] unit-test config summaries and blocker behavior first
- [ ] add pure tests for refresh-policy helpers before runtime store work
- [ ] keep backing-store behavior behind later targeted integration tests

## Atomic commit strategy

- [ ] `mlcache: add pure cache model scaffold`
- [ ] `mlcache: add fetch-on-miss semantics helpers`
- [ ] `mlcache: add first shared backing adapter`
- [ ] `docs: document authz feature_flags webhook and session composition with mlcache`

## Verification checklist

- [ ] `bun scripts/test.js mlcache` — unit tests pass
- [ ] `bun test modules/mlcache/tests/basic/do.test.js` — basic integration passes
