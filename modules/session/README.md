# nginz_njs_session

Session-state scaffold for nginx written in Gleam. The long-term goal is a reusable session library with cookie and lifecycle modeling in Gleam and a runtime backing layer that targets the njs built-in `ngx.shared` dict.

## Roadmap position

`session` is a Tier-2 module in `ROADMAP.md`. The intended server-side storage target is the njs built-in `ngx.shared` — no native nginz dependency is required, but the real adapter is not wired yet.

## Design goals

- keep session shape, cookie semantics, and backend choice modeled as pure values
- separate session policy from runtime storage details
- let `authz` and `feature_flags` consume session-derived facts rather than embedding session issuance logic

## What is implemented

**`session/model.gleam`**
- `CookieConfig`, `StoreBackend`, and `SessionDescriptor`
- `default_descriptor`, `summary`

**`nginz_njs_session.gleam`**
- `describe` — returns a stable summary of the scaffolded session descriptor

**Integration tests**
- `tests/basic/` — verifies the descriptive scaffold path with stock nginx only

## Core abstractions

- `CookieConfig` — reusable cookie/session boundary configuration
- `StoreBackend` — runtime storage strategy as a value, not hidden mutable state
- `SessionDescriptor` — the reusable session contract other modules should consume

The architectural rule for this module is: session lifecycle and policy belong in a reusable Gleam library; runtime store adapters are a later boundary layered on top.

## Cross-module composition boundary

- `authz` should later consume session-derived identity or claims rather than embedding session logic
- `feature_flags` may later use session subject/key information for targeting
- `mlcache` may later complement runtime lookup patterns, but `session` should continue to own session semantics rather than generic cache policy

## Scripted core vs optional native integration

### Scripted core

- session descriptor modeling
- cookie/session lifecycle policy
- pure encode/decode and validation helpers
- session descriptors intended for a future `ngx.shared`-backed runtime adapter

### Optional native integration

- none required for the primitive; the actual `ngx.shared` adapter remains future work

## Phased implementation plan

### Phase 1 — stabilize the session descriptor model

Goal: define reusable session shapes before runtime storage exists.

- [ ] expand descriptor types with TTL, rotation, and subject metadata
- [ ] keep cookie configuration pure and testable
- [ ] add validation for insecure or conflicting cookie/session settings

### Phase 2 — add pure session value helpers

Goal: support future issuance and validation without coupling to backing stores.

- [ ] add token/cookie shape helpers
- [ ] add pure expiry and rotation rules
- [ ] document how `authz` should consume session facts instead of duplicating them

### Phase 3 — add backing-store adapters

Goal: connect the reusable session model to runtime state.

- [ ] add the first `ngx.shared`-backed session store adapter
- [ ] document fallback store boundaries without collapsing store policy into the core model
- [ ] keep backing-store failure separate from session semantics

## TDD plan

- [ ] unit-test descriptor defaults and summaries first
- [ ] add pure tests for cookie/expiry helpers before any runtime storage work
- [ ] keep backing-store behavior behind later targeted integration tests

## Atomic commit strategy

- [ ] `session: add pure session descriptor scaffold`
- [ ] `session: add pure session lifecycle helpers`
- [ ] `session: add ngx.shared-backed session store adapter`
- [ ] `docs: document authz and feature_flags composition with session`

## Verification checklist

- [ ] `bun scripts/test.js session` — unit tests pass
- [ ] `bun test modules/session/tests/basic/do.test.js` — basic integration passes
