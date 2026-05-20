# nginz_njs_authz

Policy-based authorization for nginx written in Gleam. Rules are pure functions; policies are compositions of rules. No hidden state, fully unit-testable without nginx.

## Use Case

**The problem**: access rules usually start simple and then become scattered everywhere. One path checks methods, another checks JWT roles, another calls an external policy service, and soon nobody can clearly explain why a request was allowed or denied.

**How it solves it**: this module gives you one place to express those decisions as readable rules. Instead of burying policy inside tangled nginx config, you can describe the intent clearly, combine rules safely, and keep the final answer visible: allow, or deny for a specific reason. It stays simple when the policy is simple, and still gives you room to grow into something much more serious.

**When you would use this**: use it when nginx is the front door and you want that front door to make access decisions consistently. It fits role-based access, route protection, session checks, and “ask another service before allowing this through” scenarios.

## Design goals

- A single `Decision` type (`Allow` | `Deny(status: Int, reason: String)`) flows through every rule — no exceptions, no side channels
- Rules are first-class values: `Rule = fn(Context) -> Decision`
- Combinators (`all_of`, `any_of`, `not_`) let you build arbitrary policy trees from atomic rules
- The native jwt module (optional) handles cryptographic verification; this module reads the resulting nginx variables and applies claim-based policy in Gleam
- Deny reasons are always explicit strings — operators can log them; callers can inspect them in tests

## Exports

| Handler | nginx directive | Description |
|---|---|---|
| `main.check` | `js_content` | Method whitelist; returns 204 or the `Deny` status |
| `main.jwt_check` | `js_content` | Reads `$jwt_claim_*` vars and checks role claim |
| `main.remote_check` | `js_content` | POSTs to OPA-compatible endpoint; returns 204 or the `Deny` status |
| `main.cached_remote_check` | `js_content` | `remote_check` with `ngx.shared` cache keyed by Bearer token SHA-256 |
| `main.enriched_check` | `js_content` | `check` + sets `X-Authz-Status` response header |
| `main.enriched_jwt_check` | `js_content` | `jwt_check` + sets `X-Authz-Status` and `X-Authz-<Claim>` headers |
| `main.enriched_remote_check` | `js_content` | `remote_check` + sets `X-Authz-Status` response header |
| `main.session_gate` | `js_content` | Verifies a session cookie via the shared session store; returns 204 + `X-Session-Subject` or 401 |
| `main.oidc_check` | `js_content` | Reads `$oidc_claim_*` vars; requires `sub` to be present (authenticated OIDC identity) |
| `main.enriched_oidc_check` | `js_content` | `oidc_check` + sets `X-Authz-Status` and `X-Authz-<Claim>` headers |
| `main.enriched_composed_check` | `js_content` | Canonical Milestone 3 recipe: merges JWT + OIDC identity, query extraction, and WAF / nftset allow-path facts into one policy tree |
| `main.enriched_milestone3_check` | `js_content` | Full Milestone 3 shell: JWT + OIDC + session + query + bundled WAF/nftset + remote OPA, with structured `X-Authz-*` decision facts |
| `main.waf_check` | `js_content` | Allow-path WAF check: reads `$waf_result`; passes on "allowed"/"dryrun", denies on "denied" |
| `main.nftset_check` | `js_content` | Allow-path nftset check: reads `$nftset_result`; passes on "allow" or absent |

## nginx configuration

### Basic method check

```nginx
http {
    js_engine qjs;
    js_path "njs/";
    js_import main from app.js;
    server {
        listen 8888;
        location /api/ { js_content main.check; }
        location /admin/ {
            jwt_secret "your-secret";
            jwt_claim $jwt_claim_role role;
            js_content main.jwt_check;
        }
    }
}
```

### Remote OPA decision point

```nginx
location /api/ {
    set $authz_opa_url http://opa.internal:8181/v1/data/authz/allow;
    js_content main.remote_check;
}
```

Sends `{"input":{"method":"…","path":"…","remote_addr":"…"}}`, expects `{"result":{"allow":true|false}}`.

### Cached remote check

```nginx
js_shared_dict_zone zone=authz_cache:10m timeout=1h;
…
location /api/ {
    set $authz_opa_url  http://opa.internal:8181/v1/data/authz/allow;
    set $authz_cache_ttl 300;   # seconds; default 300 if unset
    js_content main.cached_remote_check;
}
```

`timeout=` on `js_shared_dict_zone` is required for per-key TTL.

### Downstream header injection with auth_request

```nginx
location /protected/ {
    auth_request     /auth;
    auth_request_set $authz_status $upstream_http_x_authz_status;
    auth_request_set $authz_role   $upstream_http_x_authz_role;
    proxy_set_header X-User-Role   $authz_role;
    proxy_pass       http://backend;
}
location = /auth {
    internal;
    set $authz_opa_url http://opa.internal:8181/v1/data/authz/allow;
    js_content main.enriched_remote_check;
}
```

### Canonical composed policy shell

```nginx
location = /auth/composed {
    internal;

    # Production deployments usually get these from native jwt / oidc / waf /
    # nftset modules. The test fixture simulates them from request headers.
    set $jwt_claim_role      $http_x_jwt_role;
    set $oidc_claim_sub      $http_x_oidc_sub;
    set $oidc_claim_email    $http_x_oidc_email;
    set $oidc_claim_name     $http_x_oidc_name;
    set $waf_result          $http_x_waf_result;
    set $waf_category        $http_x_waf_category;
    set $waf_rule_id         $http_x_waf_rule_id;
    set $waf_score           $http_x_waf_score;
    set $nftset_result       $http_x_nftset_result;
    set $nftset_matched_set  $http_x_nftset_matched_set;

    js_content main.enriched_composed_check;
}
```

This handler demonstrates the intended Milestone 3 shape: one policy tree over
identity claims, request query, and phase-safe native security signals, while
still keeping body ownership and rendering outside `authz`.

Important contract notes for this recipe:

- `identity.with_jwt_and_oidc(...)` gives JWT claims precedence on key collisions.
  In practice that means a claim like `sub` will come from `$jwt_claim_sub` when
  both JWT and OIDC provide it; OIDC fills the gaps for fields JWT did not set.
- The header-to-variable mapping shown above is a **test/demo fixture pattern**.
  In production, those variables should come from trusted native modules or
  controlled internal locations, not directly from arbitrary client headers.
- `main.enriched_composed_check` injects `X-Authz-*` headers on both allow and
  deny paths by design so `auth_request` callers can still inspect the decision
  context. Treat those headers as part of an internal auth contract, not a
  public response surface.

### Full Milestone 3 shell

```nginx
js_shared_dict_zone zone=sessions:1m timeout=1h;

location = /auth/milestone3 {
    internal;

    set $session_dict        sessions;
    set $authz_opa_url       http://opa.internal:8181/v1/data/authz/allow;

    # In production these come from trusted native modules or internal
    # locations. The test fixture simulates them from request headers.
    set $jwt_claim_role      $http_x_jwt_role;
    set $jwt_claim_sub       $http_x_jwt_sub;
    set $oidc_claim_sub      $http_x_oidc_sub;
    set $oidc_claim_email    $http_x_oidc_email;
    set $oidc_claim_name     $http_x_oidc_name;
    set $waf_result          $http_x_waf_result;
    set $waf_category        $http_x_waf_category;
    set $waf_rule_id         $http_x_waf_rule_id;
    set $waf_score           $http_x_waf_score;
    set $nftset_result       $http_x_nftset_result;
    set $nftset_matched_set  $http_x_nftset_matched_set;

    js_content main.enriched_milestone3_check;
}
```

`main.enriched_milestone3_check` extends the composed shell in two directions:

- it requires a live session subject from the shared session store
- it runs a remote OPA-compatible decision after the local JWT/OIDC/query/security checks pass

The handler emits structured decision facts in response headers:

- `X-Authz-Status`
- `X-Authz-Decision-Code`
- `X-Authz-Reason` on deny
- `X-Authz-Query-<Param>` for extracted query fields
- `X-Authz-Session-Subject` when a live session exists

That surface is intentionally designed for downstream consumers such as
`auth_request` locations, `response_templating`, or `response_transform`.
`authz` still owns the decision. Rendering and body mutation stay outside it.

## Policy model

Rules are functions `fn(Context) -> Decision`. Combine with `all_of`, `any_of`, `not_`:

```gleam
import authz/policy.{all_of, any_of, claim_contains_one_of, method_in, path_prefix, query_param_one_of}

let api_policy = all_of([
  method_in(["GET", "POST"]),
  path_prefix("/api"),
  any_of([claim_contains_one_of("role", ["admin", "user"])]),
  query_param_one_of("version", ["v1", "v2"]),
])
```

`evaluate(ctx, rules)` short-circuits on the first `Deny`.

Focused composed example using the same pieces as `main.enriched_composed_check`:

```gleam
import authz/policy.{all_of, claim_contains_one_of, claim_present, method_in, query_param_one_of}

let composed_policy = all_of([
  method_in(["GET"]),
  claim_present("sub"),
  claim_present("email"),
  claim_contains_one_of("role", ["admin", "support"]),
  query_param_one_of("view", ["summary", "full"]),
])
```

### Rule combinators

| Function | Description |
|---|---|
| `method_in(methods)` | Allow if request method is in the list |
| `path_prefix(prefix)` | Allow if request path starts with prefix |
| `require_header(name, value)` | Allow if header equals value exactly |
| `header_one_of(name, values)` | Allow if header is one of the values |
| `has_claim(key, value)` | Allow if claim equals value exactly |
| `claim_one_of(key, values)` | Allow if claim is one of the values |
| `claim_contains(key, value)` | Allow if comma-separated claim contains value as a segment |
| `claim_contains_one_of(key, values)` | Allow if comma-separated claim contains any value from the list |
| `query_param(key, value)` | Allow if query parameter equals value exactly |
| `query_param_one_of(key, values)` | Allow if query parameter is one of the values |
| `remote_addr_in(cidrs)` | Allow if remote address falls within any CIDR (`"10.0.0.0/8"` or plain IP) |
| `all_of(rules)` | Allow only if every rule allows (AND) |
| `any_of(rules)` | Allow if at least one rule allows (OR) |
| `not_(rule)` | Invert a rule |
| `deny_401(reason)` | Pure constructor — `Deny(401, reason)` |
| `deny_403(reason)` | Pure constructor — `Deny(403, reason)` |

### Async rules

```gleam
import authz/policy.{AsyncRule, async_evaluate, to_async}

// Lift sync rules and mix with async ones
let rules: List(AsyncRule) = [
  to_async(method_in(["GET"])),
  to_async(path_prefix("/api")),
  remote.opa_allow(_, endpoint, 2000),  // already AsyncRule
]
async_evaluate(ctx, rules)  // Promise(Decision), short-circuits on Deny
```

### Library modules

| Module | Purpose |
|---|---|
| `authz/policy` | Core types (`Context`, `Decision`, `Rule`, `AsyncRule`), all combinators, `deny_401`/`deny_403` |
| `authz/claims` | `from_request(r, names)` — extracts `$jwt_claim_<name>` nginx vars into claims dict |
| `authz/query` | `from_request(r, names)` — extracts `$arg_<name>` nginx vars into query dict |
| `authz/remote` | `opa_allow(ctx, endpoint, timeout_ms)` — async OPA-compatible remote check via `http_client` |
| `authz/cache` | `lookup/store` — `ngx.shared`-backed decision cache keyed by Bearer token SHA-256 |
| `authz/enrich` | `inject_status/inject_claims/inject_security_facts/inject_facts` — sets `X-Authz-*` response headers |
| `authz/facts` | `decision/query/session_subject/security/compose` — pure structured facts for downstream templating or response shaping |
| `authz/subrequest` | `auth_request_step(r, path)` — AsyncRule backed by nginx subrequest |
| `authz/oidc` | `from_request(r)` — reads `$oidc_claim_sub/email/name` into a claims dict; `identity_from_request(r)` — typed `OidcIdentity` |
| `authz/identity` | `from_request/with_jwt/with_oidc/with_jwt_and_oidc` — request-to-context builders for canonical policy recipes |
| `authz/security` | `SecurityFacts`, `from_request(r)`, `pass`, `pass_rule` — bundled phase-safe WAF/nftset normalization and allow-path composition |

## What is implemented

**`authz/policy.gleam`**
- `Context` — method, path, remote_addr, headers, claims, query, body
- `Decision` — `Allow` | `Deny(status: Int, reason: String)`
- `Rule = fn(Context) -> Decision` and `AsyncRule = fn(Context) -> Promise(Decision)`
- `evaluate` — short-circuits on first `Deny`
- `async_evaluate` — async short-circuit evaluation; `to_async` lifts a sync Rule
- Atomic rules: `method_in`, `path_prefix`, `require_header`, `header_one_of`, `has_claim`, `claim_one_of`, `claim_contains`, `claim_contains_one_of`, `query_param`, `query_param_one_of`, `remote_addr_in`
- Combinators: `all_of`, `any_of`, `not_`
- Helpers: `deny_401(reason)`, `deny_403(reason)`

**`authz/claims.gleam`** — `from_request` reads any list of `jwt_claim_*` nginx variables

**`authz/query.gleam`** — `from_request` reads any list of `arg_*` nginx variables

**`authz/remote.gleam`** — `opa_allow` POSTs context to an OPA-compatible endpoint via `http_client`

**`authz/cache.gleam`** — `lookup`/`store` backed by `mlcache/shared` with per-key TTL, keyed by SHA-256 of the Bearer token

**`authz/enrich.gleam`** — `inject_status`, `inject_claims`, `inject_security_facts`, and `inject_facts` set `X-Authz-*` response headers

**`authz/subrequest.gleam`** — `auth_request_step(r, path)` builds an AsyncRule backed by `http.subrequest`; 2xx → Allow, anything else → Deny(403)

**`authz/oidc.gleam`** — `from_request` reads `$oidc_claim_sub/email/name` into a claims dict (same shape as `authz/claims`, so all existing `has_claim`/`claim_one_of` rules work); `identity_from_request` returns a typed `OidcIdentity`

**`authz/identity.gleam`** — `with_jwt_and_oidc` merges OIDC claims first, then JWT claims, so JWT wins on duplicate keys

**`authz/security.gleam`** — typed `WafFact` / `NftsetFact` parsed from native module variables; `SecurityFacts` bundles both signal families, while `pass` / `pass_rule` keep allow-path and dry-run composition readable in one policy tree

**`authz/facts.gleam`** — pure structured authz facts (`status`, `decision_code`, `reason`, `query_*`, `session_subject`, `waf_*`, `nftset_*`) for downstream modules such as `response_templating` or `response_transform`

**`nginz_njs_authz.gleam`** (njs entry point) — 15 handler exports; `enriched_composed_check` is the synchronous canonical shell, and `enriched_milestone3_check` proves the full async Milestone 3 scope over JWT, OIDC, session, query, WAF, nftset, and remote checks

**`authz/policy.gleam`** — `claim_present(key)` added: Allow if any non-empty value exists for the claim; returns `Deny(401, …)` when absent

**Integration tests**
- `tests/basic/` — method allowlist, no native deps
- `tests/opa/` — remote OPA check, no native deps
- `tests/cache/` — shared-dict cache, no native deps
- `tests/enrich/` — header injection, no native deps
- `tests/enrich/` also proves the composed policy-shell example end-to-end with simulated JWT/OIDC/WAF/nftset variables plus query extraction
- `tests/milestone3/` — full-shell integration with the session bundle plus remote OPA allow/deny
- `tests/session/` — cross-module `session_gate` flow backed by the session bundle, no native deps
- `tests/jwt/` — full JWT flow: native module verifies HS256, njs checks role (`make` required)

## Limitations

- **No runtime policy reload.** Policy rules are compiled into the njs bundle. A policy change requires rebuilding and `nginx -s reload`. Hot-patching is not supported by the njs module system.
- `jwt_check` / `enriched_jwt_check` depend on `$jwt_claim_*` variables set by the nginz native JWT module. Signature verification is the native layer's job.
- Phantom-token / OAuth introspection are intentionally **not** reimplemented as a scripted verifier here. They should be added only when a concrete trusted native JWT/introspection surface exists to populate nginx variables or an internal auth location for `authz` to consume.

## Composition boundary with response modules

Use `authz` to decide and annotate. Use response modules to render or mutate.

- `response_templating` is the right consumer when nginx should generate a fresh deny/allow body. The pure `authz/facts.compose(...)` output can be fed into `response_templating/vars.from_dict(...)` after `authz` has already made the decision.
- `response_transform` is the right consumer when an upstream body already exists and only needs shaping. `authz` can expose structured `X-Authz-*` headers through `auth_request`; a downstream location can then transform an upstream payload using those facts without moving body generation into `authz`.
- `authz` itself should not become a rendering engine. It owns decision logic and structured context, not final response-body composition.

## Upstream enabler: njs PR #1044 (landed)

Upstream njs PR `nginx/njs#1044` has merged and is now active in `submodules/njs`. It adds `js_access` plus request-body readers (`readRequestText()`, `readRequestJSON()`, `readRequestForm()`). The `ngs` package exposes these as `http.read_request_json`, `http.read_request_form`, and `http.read_request_text`.

**Phase 5 is implemented** using these APIs. Key behavioral invariants discovered during implementation:

- In `js_access`, **allow = return `Nil`** (sync) or **`promise.resolve(Nil)`** (async). Do not call anything to signal allow.
- **`http.done(r)` crashes in access phase** — it is only valid in body/header filter context. Calling it from `js_access` throws `TypeError: cannot set done while not filtering`.
- **`return 200 "..."` in nginx config bypasses `js_access`** — `return` runs in the REWRITE phase, before ACCESS. Always pair `js_access` with `js_content` (or `proxy_pass`, `echozn`) as the content handler.
- It does **not** erase the `ratelimit_policy` lesson about native ACCESS-phase deny-path state and `error_page` redirects; `js_access` strengthens scripted policy but does not fix native context loss.

## Phased implementation plan

### Phase 1 — strengthen the pure policy language ✓

- [x] `claim_one_of(key, values)` and `header_one_of(key, values)`
- [x] `claim_contains(key, value)` and `claim_contains_one_of(key, values)` — multi-value comma-separated claims
- [x] `query_param(key, value)` and `query_param_one_of(key, values)` — query string rules
- [x] `Context.query` field populated from `$arg_*` nginx variables via `authz/query.from_vars`
- [x] `remote_addr_in(cidrs)` — IPv4 allowlist/denylist with CIDR notation (`"10.0.0.0/8"`, `"1.2.3.4"`)
- [ ] `path_matches(pattern)` — regex/glob path matching (needs JS regex FFI)
- [ ] focused examples showing nested `all_of` / `any_of` policy trees

### Phase 2 — make decisions richer without losing purity ✓

- [x] `X-Authz-Status` and `X-Authz-<Claim>` response headers via `authz/enrich`
- [x] `apply_decision(r, decision, log_prefix)` nginx adapter in the entry point
- [x] `Deny` carries HTTP status code — `Deny(status: Int, reason: String)`
- [x] `deny_401(reason)` and `deny_403(reason)` pure constructor helpers
- [x] nginx handlers use the status from `Deny` (401 vs 403 semantics end-to-end)

### Phase 3 — async policy adapters ✓

- [x] `AsyncRule = fn(Context) -> Promise(Decision)` type alias in `policy.gleam`
- [x] `async_evaluate(ctx, rules)` — async short-circuit evaluation
- [x] `to_async(rule)` — lifts a sync `Rule` into an `AsyncRule`
- [x] `authz/remote.opa_allow` — async OPA-compatible external check via `http_client`
- [x] integration test coverage for external auth service (`tests/opa/`, `tests/cache/`)
- [x] `authz/subrequest.auth_request_step(r, path)` — AsyncRule backed by nginx subrequest; 2xx → Allow

### Phase 4 — compose policy outputs in nginx ✓

- [x] `X-Authz-Status` / `X-Authz-<Claim>` headers for `auth_request` enrichment flows
- [x] `ngx.shared` decision cache (`authz/cache`) for introspection result reuse
- [x] `cached_remote_check` handler wiring cache + OPA + Bearer token extraction
- [x] reusable RBAC recipe documentation (path+method+role policy tree)
- [ ] document optional jwt module wiring end-to-end

### Phase 5 — access-phase adapters ✓

Goal: add access-phase adapters without changing the core policy DSL. Unblocked once njs PR #1044 landed in the submodule and `ngs` exposed request-body APIs.

- [x] `js_access` sync adapter (`access_check`) — method/header/claim gates before content phase
- [x] `js_access` async JSON body adapter (`access_json_check`) — body params extracted via `$authz_body_fields`, required field checked via `$authz_body_required`
- [x] `js_access` async form body adapter (`access_form_check`) — same pattern for `application/x-www-form-urlencoded`
- [x] `Context.body` field (mirrors `Context.query`) populated from JSON/form body via `authz/body`
- [x] body rules: `body_param`, `body_param_one_of`, `body_param_present`
- [x] integration test coverage (`tests/access/`) for all three handlers including allow/deny paths
- [x] documented behavioral invariant: allow = return `Nil`/`promise.resolve(Nil)`; never call `http.done()` from `js_access`

### Phase 6 — absorb broader security and identity adapters ✓

Goal: extend the existing `Decision`-based policy engine instead of reviving parallel packages for security signals or OIDC plumbing.

- [x] `authz/oidc` helpers that normalize `$oidc_claim_*` inputs into the existing policy context and claim dictionary
- [x] identity-mapping helpers for common OIDC fields (`sub`, `email`, `name`) so downstream policy stays inside one DSL
- [x] typed phase-safe security facts for native `$waf_*` and `$nftset_*` variables
- [x] rule helpers for allow-path / dry-run composition over WAF and nftset facts without promising generic deny-path reconstruction through `error_page`
- [x] `claim_present(key)` added to policy DSL — needed by OIDC identity gates where subject must be present but exact value is not known at policy-write time
- [x] end-to-end docs showing JWT, OIDC, WAF, and nftset wiring into one policy tree

### Phase 7 — milestone 3 policy completion and response composition

Goal: make `authz` feel like the complete scripted security shell while keeping rendering, transport, and native primitives in their proper homes.

- [x] complete the documented OIDC + WAF + nftset adapters from Phase 6 with stable request-to-context examples and recipes
- [x] add reusable security-fact normalization helpers that keep allow-path and dry-run composition readable in one policy tree
- [x] add composition examples where `authz` emits structured deny/allow context that `response_templating` or `response_transform` can consume without moving body ownership into `authz`
- [x] keep phantom-token / OAuth introspection explicitly gated on a concrete native JWT/introspection surface rather than inventing a parallel scripted verifier
- [x] integration/docs proving the Milestone 3 scope as one policy DSL over JWT, OIDC, WAF, nftset, session, and remote checks

## TDD plan

- [x] unit-test each atomic rule in isolation
- [x] unit-test combinator nesting and short-circuit behavior
- [x] unit-test `async_evaluate` / `to_async` with sync rules
- [x] unit-test `query_param` and `query_param_one_of`
- [x] unit-test decision helper semantics when `Deny` carries HTTP status (`deny_401`, `deny_403`, status propagation)
- [ ] `tests/basic/` scenario for request-to-context extraction correctness
- [x] native JWT scenario as optional proof of composition with nginz (`tests/jwt/`)
- [x] unit-test OIDC claim normalization and identity mapping helpers (`claim_present`)
- [x] unit-test WAF / nftset fact parsing and bundled rule composition (`waf_pass`, `nftset_pass`, `security.pass`)
- [x] integration/docs proving one composed request-to-context recipe over JWT, OIDC, query, WAF, and nftset inputs (`tests/enrich/`, `main.enriched_composed_check`)
- [x] integration/docs proving the full Milestone 3 shell over JWT, OIDC, WAF, nftset, session, and remote checks (`tests/milestone3/`, `main.enriched_milestone3_check`)
- [ ] native integration scenarios proving only the documented phase-safe WAF / nftset paths

## Verification checklist

- [x] `bun scripts/test.js authz` — 86 unit tests pass
- [x] `bun test modules/authz/tests/basic/do.test.js` — method allowlist passes
- [x] `bun test modules/authz/tests/opa/do.test.js` — remote OPA check passes
- [x] `bun test modules/authz/tests/cache/do.test.js` — shared-dict cache passes
- [x] `bun test modules/authz/tests/enrich/do.test.js` — header injection passes
- [x] `bun test modules/authz/tests/milestone3/do.test.js` — full Milestone 3 shell passes
- [x] `bun test modules/authz/tests/session/do.test.js` — session-backed `session_gate` passes
- [x] `bun test modules/authz/tests/jwt/do.test.js` — JWT integration passes (`make` required)
- [x] `bun test modules/authz/tests/oidc/do.test.js` — OIDC identity mapping and policy composition pass
- [x] `bun test modules/authz/tests/security_signals/do.test.js` — documented WAF / nftset allow-path composition passes
- [x] `bun test modules/authz/tests/enrich/do.test.js` — canonical composed policy-shell recipe passes
- [ ] Manual: configure a real RBAC policy, hit with admin/user/guest tokens, verify log output
- [ ] Load test: 10k req/s baseline through the `check` handler to measure njs overhead
