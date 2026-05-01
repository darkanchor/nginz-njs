# nginz_njs_webhook

Webhook signing and callback-verification for nginx written in Gleam. Composes `http_client` for outbound delivery and njs Web Crypto for HMAC signing/verification.

## Roadmap position

`webhook` is a Tier-2 module in `ROADMAP.md`. It has no native blocker because HMAC and related cryptographic primitives live in njs Web Crypto, while the scripted layer owns vendor-specific delivery and verification semantics.

## Design goals

- keep outbound and inbound webhook behavior modeled as pure config values first
- compose `http_client` for delivery instead of re-owning HTTP execution
- separate signing/verification semantics from transport and retry policy
- keep nginx handlers thin and demonstrative

## What is implemented

**`webhook/spec.gleam`** — config model + validation
- `Algorithm` — `HmacSha256`
- `DeliveryMode` — `Outbound`, `Inbound`
- `WebhookConfig` — name, algorithm, delivery_mode, signature_header, url, secret, headers, timeout_ms, retry_max_attempts
- `ConfigError` — 6 typed validation errors (EmptyName, EmptyUrl, EmptySecret, InvalidTimeout, InvalidRetryAttempts, MissingSignatureHeader)
- `validate()` — validates config completeness and value bounds
- `demo_outbound()` / `demo_inbound()` — example configs
- `summary()`, `error_text()`, `default_timeout_ms()`, `default_retry_max_attempts()`

**`webhook/sign.gleam`** — HMAC signing/verification over njs Web Crypto
- `sign(config, payload)` → `Promise(String)` — hex-encoded HMAC-SHA256
- `verify(config, payload, signature)` → `Promise(Bool)` — case-insensitive, constant-time comparison
- `signature_header(config, signature)` → `#(String, String)` — builds the header tuple

**`webhook/deliver.gleam`** — outbound delivery composing `http_client`
- `deliver(config, payload)` → `Promise(Result(Response, DeliveryError))` — signs + delivers
- `deliver_with_retry(config, payload)` → `Promise(Result(Response, DeliveryError))` — retries on timeouts, fetch failures, and 5xx
- `DeliveryError` — ConfigInvalid, SignFailed, UpstreamFailed(wraps fetch.ClientError)

**`webhook/verify.gleam`** — inbound callback verification
- `extract_signature(headers, config)` → `Result(String, VerifyError)` — case-insensitive header extraction
- `verify_request(headers, body, config)` → `Promise(Result(Nil, VerifyError))` — full verification
- `VerifyError` — MissingSignature, InvalidSignature, InvalidPayload

**`nginz_njs_webhook.gleam`** — njs entry point
- `describe_outbound` / `describe_inbound` — stable config summaries (scaffold)
- `sign_demo` — signs a JSON payload and returns the hex signature
- `verify_demo` — verifies an inbound request's signature header against the body
- `signed_fixture` — returns a signed payload fixture for integration testing
- `deliver_demo` — signs and delivers a webhook (requires upstream fixture)

**Integration tests**
- `tests/basic/` — 9 scenarios: describe handlers, HMAC signing, signed fixture, verification (valid/invalid/missing), determinism

## Core abstractions

- `WebhookConfig` — the reusable webhook descriptor
- `Algorithm` — signing primitive choice (HMAC-SHA256)
- `DeliveryMode` — outbound vs inbound usage shape
- `DeliveryError` / `VerifyError` — typed failure domains
- Signing/verification helpers layer on top of njs Web Crypto

## Cross-module composition boundary

- `webhook` consumes `http_client` for outbound delivery (`deliver`)
- `webhook` consumes `metrics` (via transitive dep on `nginz_njs_metrics` helpers)
- `mlcache` may later cache idempotency/replay metadata, but `webhook` should not absorb general cache policy
- `response_transform` may later shape callback payloads

## Scripted core vs optional native integration

### Scripted core

- webhook config modeling
- HMAC signing/verification via njs Web Crypto
- delivery orchestration built on `http_client`
- callback verification and signature extraction
- typed error domains for delivery and verification

### Optional native integration

- none required for the baseline
- future stateful replay protection may later pair with `mlcache` or other native-backed state primitives

## Phased implementation plan

### Phase 1 — stabilize the webhook config model ✅

Goal: define reusable webhook descriptors before wiring crypto or transport.

- [x] expand `WebhookConfig` with headers, secret metadata, delivery targets, timeout, retry
- [x] keep outbound/inbound modeling explicit and pure
- [x] add `validate()` with typed `ConfigError`

### Phase 2 — add outbound delivery composition ✅

Goal: make outbound webhook delivery a composition over `http_client`.

- [x] define the payload-to-request mapping layer (`deliver`)
- [x] compose `http_client` for actual delivery
- [x] add retry policy (`deliver_with_retry`) with typed retryable error detection

### Phase 3 — add inbound verification helpers ✅

Goal: support callback verification without collapsing all protocol behavior into handlers.

- [x] add HMAC signing and verification on top of config model (`sign`)
- [x] separate signature parsing (`extract_signature`) from business-policy decisions (`verify_request`)
- [x] case-insensitive header lookup and signature comparison

### Phase 4 — add operational glue

- [ ] add idempotency/replay patterns via `mlcache`
- [ ] add payload normalization via `response_transform`
- [ ] add metrics hooks via `metrics` helpers

## TDD plan

- [x] unit-test config summary and validation (11 tests)
- [x] unit-test HMAC signing determinism and round-trip verification (9 tests)
- [x] unit-test signature extraction and full request verification (6 tests)
- [x] unit-test DeliveryError discriminators (2 tests)
- [x] add integration coverage for signing, fixture, and verification flows (9 tests)

## Atomic commit strategy

- [x] `webhook: add pure webhook spec with validation`
- [x] `webhook: add HMAC signing and verification over njs Web Crypto`
- [x] `webhook: add outbound delivery composition over http_client`
- [x] `webhook: add inbound verification helpers`
- [x] `docs: document webhook composition with http_client`

## Verification checklist

- [x] `bun scripts/test.js webhook` — 28 unit tests pass
- [x] `bun test ./modules/webhook/tests/basic/do.test.js` — 9 integration tests pass
- [x] `bun run build:module webhook` — builds successfully
- [x] `bun scripts/test.js` — all 9 modules pass, zero regressions
