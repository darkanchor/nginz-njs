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

## Batched todos

### Batch 1 — richer context and rules
- [ ] Add query parameters to `Context` (parse from `http.uri`)
- [ ] Add `path_matches(pattern)` rule using glob or regex
- [ ] Add `remote_addr_in(cidrs)` rule for IP allowlist / denylist
- [ ] Add `claim_one_of(key, values)` for multi-value claim matching

### Batch 2 — response control
- [ ] Let `Deny` carry an HTTP status code alongside the reason (`Deny(status: Int, reason: String)`)
- [ ] Add `return_denied(r, decision)` helper that writes a JSON error body instead of bare status code
- [ ] Propagate deny reason as a response header for upstream logging

### Batch 3 — async rules
- [ ] Define `AsyncRule = fn(Context) -> Promise(Decision)` and `evaluate_async`
- [ ] Add `auth_request_step(path)` — delegates to a subrequest and maps 2xx → Allow, 4xx → Deny
- [ ] Integration test: external authz service via subrequest

### Batch 4 — production hardening
- [ ] Expose `$authz_decision` and `$authz_reason` as nginx variables (via `js_set`) so upstream access logs capture them
- [ ] Add `js_set`-based variant that runs policy in the access phase (non-blocking, no subrequest)
- [ ] Document the jwt module variable names and `jwt_claim` directive setup

## Verification checklist

- [ ] `bun scripts/test.js authz` — all 17 unit tests pass
- [ ] `bun test modules/authz/tests/basic/do.test.js` — method allowlist integration passes
- [ ] `bun test modules/authz/tests/jwt/do.test.js` — JWT integration passes (`make` required)
- [ ] Manual: configure a real RBAC policy, hit with admin/user/guest tokens, verify log output
- [ ] Load test: 10k req/s baseline through the `check` handler to measure njs overhead
