# nginz_njs_security_gateway

Unified security policy composition. The pure policy layer reads `$jwt_claim_*`, `$oidc_claim_*`, and `$ratelimit_result` nginx variables and composes them into a single allow/deny/challenge decision in Gleam.

## Roadmap position

Sprint 6 (security composition) in Milestone 2 of `ROADMAP.md`. Depends on the native nginz `jwt`, `oidc`, and `ratelimit` modules. Composes with `authz`, `session`, `feature_flags`, `http_client`, `metrics`, and `response_transform`.

## Design goals

- Read `$jwt_claim_*`, `$oidc_claim_*`, and `$ratelimit_result` from nginx variables set by native modules
- Compose security signals into a single `SecurityDecision` using `all_of` / `any_of` / `not_` patterns (same FP model as `authz`)
- Render custom error responses per denial reason (401, 403, 429)
- Render challenge pages for borderline requests (login redirect, CAPTCHA placeholder)
- Keep policy pure and testable — native modules own signal generation, this module owns composition

## Core abstractions

- `SecuritySignal` — `JwtAuthenticated`, `JwtAnonymous`, `OidcIdentity`, `OidcAnonymous`, `RateLimit`, `IpReputation`, `WafDetection`: typed signals from native modules
- `SecurityDecision` — `Allow`, `Deny(status, reason)`, `Challenge(status, reason, type)`: the unified policy outcome
- `Rule` — `fn(List(SecuritySignal)) -> SecurityDecision`: composable policy functions

The evaluator is side-effect free: it transforms native module variables into typed signals, signals into decisions via rule composition, and decisions into HTTP responses. Signal generation and HTTP response belong at the nginx adapter boundary.

## Scripted core vs optional native integration

### Scripted core

- Signal composition: combining JWT, OIDC, rate limit signals into unified policy
- Rule evaluation: `all_of`, `any_of`, `not_` combinators for arbitrary policy trees
- Response rendering: JSON error bodies, challenge pages per denial reason
- Reusable library surface: `model`, `evaluate`, `challenge`, `response`, `metrics` modules

### Optional native integration

- Native `jwt` module: verifies JWT signatures, sets `$jwt_claim_*` variables
- Native `oidc` module: handles OIDC flows, sets `$oidc_claim_*` variables
- Native `ratelimit` module: manages shared-memory counters, sets `$ratelimit_*` variables

Native modules run in ACCESS phase; this module runs in CONTENT phase.

Native modules own signal generation (cryptographic verification, counter logic). This module owns policy composition and response shaping.

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.evaluate_security` | `js_content` | Reads all signals, evaluates policy, returns allow/deny/challenge |
| `main.evaluate_with_metrics` | `js_content` | Same as evaluate_security |
| `main.challenge_handler` | `js_content` | Issues challenge (307 redirect) for anonymous, 204 for authenticated |

## nginx configuration

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;

    server {
        listen 8888;

        location /security/evaluate { js_content main.evaluate_security; }
        location /security/metrics   { js_content main.evaluate_with_metrics; }
        location /security/challenge { js_content main.challenge_handler; }
    }
}
```

## Library modules

| Module | Purpose |
|---|---|
| `security_gateway/model` | `SecuritySignal`, `SecurityDecision`, signal constructors, summary helpers |
| `security_gateway/evaluate` | `Rule`, `evaluate`, `all_of`, `any_of`, `not_`, pre-built signal rules |
| `security_gateway/challenge` | `login_redirect`, `text_challenge`, `json_challenge` — challenge page renderers |
| `security_gateway/response` | `json_401`, `json_403`, `json_429`, `text_error` — error body renderers |
| `security_gateway/metrics` | `decision_counter`, `denied_counter`, `challenge_counter` — security metrics |

## What is implemented

**`security_gateway/model.gleam`**
- `SecuritySignal` — `JwtAuthenticated`, `JwtAnonymous`, `OidcIdentity`, `OidcAnonymous`, `RateLimit`, `IpReputation`, `WafDetection`
- `SecurityDecision` — `Allow`, `Deny(status, reason)`, `Challenge(status, reason, type)`
- Constructors: `jwt_authenticated`, `jwt_anonymous`, `oidc_identity`, `oidc_anonymous`, `rate_limit`, `ip_reputation`
- `signal_summary`, `decision_summary`

**`security_gateway/evaluate.gleam`**
- `Rule` — `fn(List(SecuritySignal)) -> SecurityDecision`
- `evaluate(signals, rules)` — fold-until evaluation (first non-Allow wins)
- `all_of`, `any_of`, `not_` — rule combinators
- Pre-built rules: `require_jwt`, `require_oidc`, `require_any_auth`, `deny_if_rate_limited`, `deny_if_ip_blocked`, `challenge_if_anonymous`

**`security_gateway/challenge.gleam`**
- `login_redirect(login_url)` — HTML meta-refresh redirect
- `text_challenge(reason, type)` — plain text
- `json_challenge(status, reason, type)` — JSON

**`security_gateway/response.gleam`**
- `json_401(reason)`, `json_403(reason)`, `json_429(reason, retry_after)`
- `text_error(status, reason)`

**`security_gateway/metrics.gleam`**
- `decision_counter(decision, route)` — allow/deny/challenge counter
- `denied_counter(status, reason, route)` — denial breakdown
- `challenge_counter(type, route)` — challenge counter

**`nginz_njs_security_gateway.gleam`** (njs entry point)
- 3 handlers: `evaluate_security`, `evaluate_with_metrics`, `challenge_handler`
- Reads `$jwt_claim_*`, `$oidc_claim_*`, `$ratelimit_*` variables
- Composes default policy: deny if rate-limited, then require any auth (JWT or OIDC)
- Default policy is hardcoded — not configurable via nginx variables

**Integration tests**
- `tests/basic/` — 8 scenarios: JWT allow, OIDC allow, anonymous deny, rate limit deny, rate limit ok, challenge redirect, challenge allow

## Cross-module composition

### authz — claim-based rules

Pass mapped claims into authz policies:

```gleam
import security_gateway/model

let signal = model.jwt_authenticated([#("sub", "user-1"), #("role", "admin")])
```

### metrics — decision emission (library available)

The `security_gateway/metrics` module provides counters for security decisions. Current entry point handlers do not emit metrics; instrumentation is a future enhancement:

```gleam
import security_gateway/metrics as sg_metrics
import metrics/line

let m = sg_metrics.decision_counter(Allow, "/api")
line.render_statsd(m)
```

### response_transform — error body shaping (future)

Apply response_transform plans differently per denial reason:

```gleam
import security_gateway/response as sg_response
import response_transform/eval

let body = sg_response.json_403("ip blocked")
```

## Completion scope

`security_gateway` is complete for its core contract as a security policy composition layer:

- Pure policy model: native signals → `SecuritySignal` list → `SecurityDecision` via rule evaluation
- Rule combinators: `all_of`, `any_of`, `not_` for arbitrary policy trees
- Response rendering: JSON error bodies (401, 403, 429), challenge pages (login redirect)
- nginx handlers: evaluate_security, evaluate_with_metrics, challenge_handler variants
- Integration test coverage for all handler variants

Future work focuses on composition through existing modules (`metrics`, `response_transform`) and native module integration (IP reputation, WAF) rather than new handler logic.

## Phased implementation plan

### Phase 1 — signal model and evaluation ✓

- [x] `security_gateway/model` — SecuritySignal, SecurityDecision, constructors
- [x] `security_gateway/evaluate` — Rule composition with all_of/any_of/not_
- [x] Basic handler: evaluate_security

### Phase 2 — responses and challenge rendering ✓

- [x] `security_gateway/response` — JSON error renderers per status code
- [x] `security_gateway/challenge` — challenge page renderers
- [x] Integration test scenarios

### Phase 3 — composition and native integration (future)

- [ ] Entry point handlers compose `security_gateway/metrics` for decision emission
- [ ] IP reputation integration (requires nftset in nginz native modules)
- [ ] WAF detection integration (requires WAF njs-facing variables)
- [ ] Dynamic policy reload from config
- [ ] Per-route differentiated security policies
- [ ] CAPTCHA service integration for challenge responses

## TDD plan

- [x] unit-test signal constructors and summaries
- [x] unit-test decision_summary formatting
- [x] unit-test evaluate: allow, deny jwt, deny rate limit, any auth, all_of, any_of, not_, challenge
- [x] unit-test challenge page rendering
- [x] unit-test response body rendering (401, 403, 429)
- [x] `tests/basic/` — 8 integration scenarios with simulated variables

## Verification checklist

- [x] `bun scripts/test.js security_gateway` — 20 unit tests pass
- [x] `bun test modules/security_gateway/tests/basic/do.test.js` — 8 integration tests pass
- [ ] `make NGINZ_MODULES="jwt oidc ratelimit" && bun run test:native` — native integration

## Limitations

- **IP reputation is a stub.** The `IpReputation` signal type exists but nftset is not packageable as a standalone `--add-module` module. Full integration requires nftset added to `build_package.zig`'s `module_infos` in the nginz repo.
- **WAF detection is a stub.** The `WafDetection` signal type exists but WAF runs in ACCESS phase with no njs-facing variables.
- **Default policy is hardcoded.** The entry point uses a single composed policy. Per-route customization requires variable-driven policy selection.
- **Challenge responses are static.** CAPTCHA integration requires an external service for challenge verification.
