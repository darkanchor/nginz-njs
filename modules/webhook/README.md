# nginz_njs_webhook

Webhook signing and callback-verification scaffold for nginx written in Gleam. The long-term goal is reusable webhook protocol glue built on top of `http_client`, not another isolated fetch abstraction.

## Roadmap position

`webhook` is a Tier-2 module in `ROADMAP.md`. It has no native blocker because HMAC and related cryptographic primitives can live in njs Web Crypto, while the scripted layer owns vendor-specific delivery and verification semantics.

## Design goals

- keep outbound and inbound webhook behavior modeled as pure config values first
- compose `http_client` for delivery instead of re-owning HTTP execution
- separate signing/verification semantics from transport and retry policy
- keep nginx handlers thin and demonstrative

## What is implemented

**`webhook/spec.gleam`**
- `Algorithm`, `DeliveryMode`, and `WebhookConfig`
- `demo_outbound`, `demo_inbound`, and `summary` scaffold helpers

**`nginz_njs_webhook.gleam`**
- `describe_outbound` — returns the outbound webhook scaffold summary
- `describe_inbound` — returns the inbound webhook scaffold summary

**Integration tests**
- `tests/basic/` — verifies stable scaffold responses with stock nginx only

## Core abstractions

- `WebhookConfig` — the reusable webhook descriptor
- `Algorithm` — signing primitive choice
- `DeliveryMode` — outbound vs inbound usage shape
- future signing/verification and dispatch helpers — these should layer on top of the config model, not replace it

The architectural rule for this module is: webhook protocol modeling belongs in a reusable Gleam surface; transport should later compose `http_client`, and payload shaping should later compose `response_transform`.

## Cross-module composition boundary

- `webhook` should consume `http_client` for outbound delivery
- `webhook` can later reuse `response_transform` for payload shaping or callback normalization
- `mlcache` may later cache idempotency/replay metadata, but `webhook` should not absorb general cache policy
- `metrics` should later observe delivery/verification outcomes rather than being implemented inline here

## Scripted core vs optional native integration

### Scripted core

- webhook config modeling
- vendor-specific signing/verification semantics
- delivery orchestration built on reusable transport primitives
- callback normalization and policy glue

### Optional native integration

- none required for the baseline scaffold
- future stateful replay protection may later pair with `mlcache` or other native-backed state primitives

## Phased implementation plan

### Phase 1 — stabilize the webhook config model

Goal: define reusable webhook descriptors before wiring crypto or transport.

- [ ] expand `WebhookConfig` with headers, secret metadata, and delivery targets
- [ ] keep outbound/inbound modeling explicit and pure
- [ ] add validation helpers for incomplete or conflicting configs

### Phase 2 — add outbound delivery composition

Goal: make outbound webhook delivery a composition over `http_client`.

- [ ] define the payload-to-request mapping layer
- [ ] compose `http_client` for actual delivery rather than re-owning fetch logic
- [ ] keep delivery policy and transport errors separate

### Phase 3 — add inbound verification helpers

Goal: support callback verification without collapsing all protocol behavior into handlers.

- [ ] add HMAC verification helpers on top of the config model
- [ ] separate signature parsing from business-policy decisions
- [ ] keep replay and cache concerns outside the pure core

### Phase 4 — add operational glue

Goal: make the module useful for real third-party integrations.

- [ ] add idempotency/replay patterns
- [ ] add payload normalization via `response_transform` where needed
- [ ] add metrics hooks instead of protocol-specific inline formatting

## TDD plan

- [ ] unit-test config summaries and validation first
- [ ] add pure tests for signing/verification helpers before network behavior
- [ ] keep outbound delivery and callback verification behind targeted integration tests later

## Atomic commit strategy

- [ ] `webhook: add pure webhook spec scaffold`
- [ ] `webhook: add outbound delivery composition over http_client`
- [ ] `webhook: add inbound verification helpers`
- [ ] `docs: document webhook composition with http_client and response_transform`

## Verification checklist

- [ ] `bun scripts/test.js webhook` — unit tests pass
- [ ] `bun test modules/webhook/tests/basic/do.test.js` — basic integration passes
