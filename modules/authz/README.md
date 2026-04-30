# nginz_njs_authz

Policy-based authorization for nginx written in Gleam. Rules are pure functions; policies are compositions of rules. No hidden state, fully unit-testable without nginx.

## Design goals

- A single `Decision` type (`Allow` | `Deny(reason)`) flows through every rule — no exceptions, no side channels
- Rules are first-class values: `Rule = fn(Context) -> Decision`
- Combinators (`all_of`, `any_of`, `not_`) let you build arbitrary policy trees from atomic rules
- The native jwt module (optional) handles cryptographic verification; this module only reads the resulting nginx variables and applies claim-based policy in Gleam
- Deny reasons are always explicit strings — operators can log them; callers can inspect them in tests

## What is implemented

**`authz/policy.gleam`**
- `Context` — method, path, remote_addr, headers, claims
- `evaluate` — short-circuits on first `Deny`
- Atomic rules: `method_in`, `path_prefix`, `require_header`, `has_claim`
- Combinators: `all_of`, `any_of`, `not_`

**`nginz_njs_authz.gleam`** (njs entry point)
- `check` — basic method allowlist; returns 204 / 403
- `jwt_check` — reads `$jwt_claim_role` set by the native jwt module; applies role-based policy

**Integration tests**
- `tests/basic/` — method allowlist, no native deps
- `tests/jwt/` — full JWT flow: native module verifies HS256 signature, njs checks role claim (`make` required)

## Roadmap position

`authz` is strategically important, but it should not lead with native-coupled features. The high-value path is to make the pure policy language strong first, then layer in nginx adapters, then add optional native-assisted or subrequest-assisted identity inputs.

This keeps the module useful even when no native `nginz` modules are present, and it avoids overfitting the public API to today's demo setup.

## Core abstractions

- `Context` — normalized request facts: method, path, remote address, headers, claims, and later query params or derived identity attributes
- `Decision` — the only policy result type; policy logic should always return a value, never throw or write directly to nginx
- `Rule = fn(Context) -> Decision` — the basic unit of composition
- `AsyncRule = fn(Context) -> Promise(Decision)` — a later adapter type for effectful policy checks without contaminating the sync core
- Combinators such as `all_of`, `any_of`, and `not_` — these are the real product surface, not the demo handlers

The design rule is simple: gather facts at the edge, evaluate policy in pure Gleam, then adapt the resulting `Decision` back into nginx behavior.

## Scripted core vs optional native integration

### Scripted core

- Request matching by method, path, header, query, remote address, and claims
- Claim-to-role mapping and policy composition
- Deny reason shaping and operator-facing explainability
- Subrequest or fetch adapters that translate remote decisions into `Decision`

### Optional native integration

- `jwt` for signature verification and claim extraction into nginx variables
- future shared-memory or cache primitives if token introspection or attribute caching becomes necessary

Native modules are not the architecture here. They are capability providers that can enrich the context seen by the pure policy layer.

Cross-module direction: remote decision points should later compose `http_client` for transport and `mlcache` for caching, rather than embedding bespoke fetch or cache layers inside `authz` itself.

## Phased implementation plan

### Phase 1 — strengthen the pure policy language

Goal: make the composable rule core useful before adding more adapters.

- [ ] extend `Context` with query params and a cleaner request-shape boundary
- [ ] add `path_matches(pattern)` for richer path matching
- [ ] add `remote_addr_in(cidrs)` for allowlist and denylist style policies
- [ ] add `claim_one_of(key, values)` and `header_one_of(key, values)` for multi-value matching
- [ ] add focused examples showing nested `all_of` / `any_of` policy trees

### Phase 2 — make decisions richer without losing purity

Goal: keep decision semantics in the core instead of scattering HTTP status logic across handlers.

- [ ] evolve `Deny` to carry status and reason
- [ ] add pure helpers such as `deny_401`, `deny_403`, `with_reason`, and `with_status`
- [ ] add a thin `return_denied(r, decision)` nginx adapter that renders the policy result
- [ ] optionally propagate decision metadata via response headers for logging and debugging

### Phase 3 — add async policy adapters

Goal: support external or delegated authorization checks without making the base rule language effectful.

- [ ] define `AsyncRule = fn(Context) -> Promise(Decision)` and `evaluate_async`
- [ ] add adapters between `Rule` and `AsyncRule`
- [ ] add `auth_request_step(path)` that maps subrequest results into `Decision`
- [ ] add integration coverage for an external auth service flow

### Phase 4 — make policy outputs easy to compose in nginx

Goal: let `authz` feed routing, logging, and upstream behavior cleanly.

- [ ] expose `js_set`-friendly outputs for decision, status, and reason
- [ ] document reusable recipes for RBAC, path+method gating, and claim-based policy
- [ ] document the optional `jwt` wiring without making it look mandatory
- [ ] prepare the policy surface for later use with shared state or introspection caches if that becomes valuable

## TDD plan

- [ ] unit-test each new atomic rule in isolation
- [ ] unit-test combinator nesting and short-circuit behavior
- [ ] unit-test decision helper semantics before adding nginx rendering helpers
- [ ] add `tests/basic/` scenarios for request-to-context extraction correctness
- [ ] keep native-backed JWT scenarios as optional proof that the module composes with `nginz`, not as the baseline contract

## Atomic commit strategy

- [ ] `authz: extend context and add richer rule primitives`
- [ ] `authz: add structured deny decisions and nginx rendering helpers`
- [ ] `authz: add async rule evaluation and subrequest adapters`
- [ ] `docs: document authz composition patterns and optional jwt wiring`

## Verification checklist

- [ ] `bun scripts/test.js authz` — all 17 unit tests pass
- [ ] `bun test modules/authz/tests/basic/do.test.js` — method allowlist integration passes
- [ ] `bun test modules/authz/tests/jwt/do.test.js` — JWT integration passes (`make` required)
- [ ] Manual: configure a real RBAC policy, hit with admin/user/guest tokens, verify log output
- [ ] Load test: 10k req/s baseline through the `check` handler to measure njs overhead
