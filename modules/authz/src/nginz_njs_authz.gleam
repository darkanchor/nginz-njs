import authz/body
import authz/cache.{Hit, Miss}
import authz/claims
import authz/enrich
import authz/facts
import authz/identity
import authz/oidc
import authz/policy.{type Context, type Decision, Allow, Context, Deny}
import authz/query
import authz/remote
import authz/security
import gleam/dict
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import session/cookie as session_cookie
import session/model as session_model
import session/store as session_store

fn context_from_request(r: HTTPRequest) -> Context {
  Context(
    method: http.method(r),
    path: http.uri(r),
    remote_addr: http.remote_address(r),
    headers: http.headers_in(r),
    claims: dict.new(),
    query: dict.new(),
    body: dict.new(),
  )
}

fn check(r: HTTPRequest) -> Nil {
  let ctx = context_from_request(r)
  let rules = [
    policy.method_in(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]),
  ]
  case policy.evaluate(ctx, rules) {
    Allow -> http.return_code(r, 204)
    Deny(status, reason) -> {
      let _ = http.log(r, "authz: denied — " <> reason)
      http.return_code(r, status)
    }
  }
}

fn jwt_check(r: HTTPRequest) -> Nil {
  let ctx =
    Context(..context_from_request(r), claims: claims.from_request(r, ["role"]))
  let rules = [
    policy.any_of([
      policy.has_claim("role", "admin"),
      policy.has_claim("role", "user"),
    ]),
  ]
  case policy.evaluate(ctx, rules) {
    Allow -> http.return_code(r, 204)
    Deny(status, reason) -> {
      let _ = http.log(r, "authz: jwt denied — " <> reason)
      http.return_code(r, status)
    }
  }
}

fn remote_check(r: HTTPRequest) -> Promise(Nil) {
  let endpoint = case http.get_variable(r, "authz_opa_url") {
    Ok(v) -> v
    Error(_) -> ""
  }
  let ctx = context_from_request(r)
  use decision <- promise.await(remote.opa_allow(ctx, endpoint, 2000))
  apply_decision(r, decision, "authz: remote denied — ")
}

fn bearer_token(r: HTTPRequest) -> String {
  case http.get_header_in(r, "authorization") {
    Ok(v) ->
      case string.split_once(v, " ") {
        Ok(#("Bearer", token)) -> token
        _ -> ""
      }
    Error(_) -> ""
  }
}

fn apply_decision(
  r: HTTPRequest,
  decision: Decision,
  log_prefix: String,
) -> Promise(Nil) {
  case decision {
    Allow -> {
      http.return_code(r, 204)
      promise.resolve(Nil)
    }
    Deny(status, reason) -> {
      let _ = http.log(r, log_prefix <> reason)
      http.return_code(r, status)
      promise.resolve(Nil)
    }
  }
}

fn apply_access_decision(
  r: HTTPRequest,
  decision: Decision,
  log_prefix: String,
) -> Promise(Nil) {
  case decision {
    Allow -> promise.resolve(Nil)
    Deny(status, reason) -> {
      let _ = http.log(r, log_prefix <> reason)
      http.return_code(r, status)
      promise.resolve(Nil)
    }
  }
}

fn configured_body_policy(
  r: HTTPRequest,
  adapter: String,
) -> Option(#(List(String), String)) {
  let field_names = case http.get_variable(r, "authz_body_fields") {
    Ok(v) ->
      v
      |> string.split(",")
      |> list.map(string.trim)
      |> list.filter(fn(s) { s != "" })
    Error(_) -> []
  }
  let required = case http.get_variable(r, "authz_body_required") {
    Ok(v) -> string.trim(v)
    Error(_) -> ""
  }
  case field_names, required {
    [], _ -> {
      let _ =
        http.log(
          r,
          "authz: access "
            <> adapter
            <> " misconfigured — no body fields configured",
        )
      http.return_code(r, 500)
      None
    }
    _, "" -> {
      let _ =
        http.log(
          r,
          "authz: access "
            <> adapter
            <> " misconfigured — authz_body_required not set",
        )
      http.return_code(r, 500)
      None
    }
    _, _ ->
      case list.contains(field_names, required) {
        True -> Some(#(field_names, required))
        False -> {
          let _ =
            http.log(
              r,
              "authz: access "
                <> adapter
                <> " misconfigured — required field missing from authz_body_fields",
            )
          http.return_code(r, 500)
          None
        }
      }
  }
}

fn session_subject_claim(r: HTTPRequest) -> Result(Option(String), Decision) {
  let dict_name = case http.get_variable(r, "session_dict") {
    Ok(v) -> v
    Error(_) -> ""
  }
  case dict_name {
    "" -> Error(Deny(503, "session dict not configured"))
    dict_name ->
      case http.get_header_in(r, "cookie") {
        Error(_) -> Ok(None)
        Ok(cookie_header) ->
          case
            session_cookie.read_id(
              cookie_header,
              session_model.default_descriptor().cookie.name,
            )
          {
            Error(_) -> Ok(None)
            Ok(sid) ->
              case session_store.load(dict_name, sid) {
                Error(_) -> Ok(None)
                Ok(subject) -> Ok(Some(subject))
              }
          }
      }
  }
}

/// Like remote_check but caches decisions in the `authz_cache` shared dict
/// keyed by a SHA-256 of the Bearer token. Reads $authz_cache_ttl (seconds,
/// default 300) and $authz_opa_url from nginx variables.
fn cached_remote_check(r: HTTPRequest) -> Promise(Nil) {
  let endpoint = case http.get_variable(r, "authz_opa_url") {
    Ok(v) -> v
    Error(_) -> ""
  }
  let ttl = case http.get_variable(r, "authz_cache_ttl") {
    Ok(v) ->
      case int.parse(v) {
        Ok(n) -> n
        Error(_) -> 300
      }
    Error(_) -> 300
  }
  let token = bearer_token(r)
  use cache_result <- promise.await(cache.lookup("authz_cache", token))
  case cache_result {
    Hit(decision) -> {
      let _ = http.log(r, "authz: cache hit")
      apply_decision(r, decision, "authz: cached deny — ")
    }
    Miss -> {
      let ctx = context_from_request(r)
      use decision <- promise.await(remote.opa_allow(ctx, endpoint, 2000))
      use _ <- promise.await(cache.store("authz_cache", token, decision, ttl))
      apply_decision(r, decision, "authz: remote denied — ")
    }
  }
}

/// Like check but injects X-Authz-Status on the response. Useful with
/// nginx auth_request so downstream locations can read the decision via
/// auth_request_set $var $upstream_http_x_authz_status.
fn enriched_check(r: HTTPRequest) -> Nil {
  let ctx = context_from_request(r)
  let rules = [
    policy.method_in(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]),
  ]
  let decision = policy.evaluate(ctx, rules)
  let _ = enrich.inject_status(r, decision)
  case decision {
    Allow -> http.return_code(r, 204)
    Deny(status, reason) -> {
      let _ = http.log(r, "authz: denied — " <> reason)
      http.return_code(r, status)
    }
  }
}

/// Like jwt_check but also injects X-Authz-Status and X-Authz-<Claim> headers
/// so upstreams receive the role without re-reading JWT variables.
fn enriched_jwt_check(r: HTTPRequest) -> Nil {
  let ctx =
    Context(
      ..context_from_request(r),
      claims: claims.from_request(r, ["role", "sub"]),
    )
  let rules = [
    policy.any_of([
      policy.has_claim("role", "admin"),
      policy.has_claim("role", "user"),
    ]),
  ]
  let decision = policy.evaluate(ctx, rules)
  let _ = enrich.inject_status(r, decision)
  let _ = enrich.inject_claims(r, ctx)
  case decision {
    Allow -> http.return_code(r, 204)
    Deny(status, reason) -> {
      let _ = http.log(r, "authz: jwt denied — " <> reason)
      http.return_code(r, status)
    }
  }
}

/// Like remote_check but injects X-Authz-Status after the OPA decision.
fn enriched_remote_check(r: HTTPRequest) -> Promise(Nil) {
  let endpoint = case http.get_variable(r, "authz_opa_url") {
    Ok(v) -> v
    Error(_) -> ""
  }
  let ctx = context_from_request(r)
  use decision <- promise.await(remote.opa_allow(ctx, endpoint, 2000))
  let _ = enrich.inject_status(r, decision)
  apply_decision(r, decision, "authz: remote denied — ")
}

/// Reads OIDC identity from $oidc_claim_* variables set by the native oidc module
/// and requires the subject claim to be present (authenticated identity).
/// Compose the returned claims into richer policy trees with claim_one_of, etc.
fn oidc_check(r: HTTPRequest) -> Nil {
  let ctx = Context(..context_from_request(r), claims: oidc.from_request(r))
  let rules = [policy.claim_present("sub")]
  case policy.evaluate(ctx, rules) {
    Allow -> http.return_code(r, 204)
    Deny(status, reason) -> {
      let _ = http.log(r, "authz: oidc denied — " <> reason)
      http.return_code(r, status)
    }
  }
}

/// Like oidc_check but also injects X-Authz-Status and X-Authz-<Claim> headers
/// so the upstream receives the OIDC identity without re-reading nginx variables.
fn enriched_oidc_check(r: HTTPRequest) -> Nil {
  let ctx = Context(..context_from_request(r), claims: oidc.from_request(r))
  let rules = [policy.claim_present("sub")]
  let decision = policy.evaluate(ctx, rules)
  let _ = enrich.inject_status(r, decision)
  let _ = enrich.inject_claims(r, ctx)
  case decision {
    Allow -> http.return_code(r, 204)
    Deny(status, reason) -> {
      let _ = http.log(r, "authz: oidc denied — " <> reason)
      http.return_code(r, status)
    }
  }
}

/// Canonical composed policy-shell example: merge JWT + OIDC identity, extract
/// request query params, and combine those facts with phase-safe WAF / nftset
/// allow-path rules in one policy tree. Designed for auth_request-style use,
/// so it injects X-Authz-* headers for the downstream location.
fn enriched_composed_check(r: HTTPRequest) -> Nil {
  let security_facts = security.from_request(r)
  let identity_ctx =
    identity.with_jwt_and_oidc(r, ["role", "sub"], ["sub", "email", "name"])
  let ctx = Context(..identity_ctx, query: query.from_request(r, ["view"]))
  let rules = [
    policy.all_of([
      policy.method_in(["GET"]),
      policy.claim_present("sub"),
      policy.claim_present("email"),
      policy.claim_contains_one_of("role", ["admin", "support"]),
      policy.query_param_one_of("view", ["summary", "full"]),
      security.pass_rule(r),
    ]),
  ]
  let decision = policy.evaluate(ctx, rules)
  let _ = enrich.inject_status(r, decision)
  let _ = enrich.inject_claims(r, ctx)
  let _ = enrich.inject_security_facts(r, security_facts)
  case decision {
    Allow -> http.return_code(r, 204)
    Deny(status, reason) -> {
      let _ = http.log(r, "authz: composed denied — " <> reason)
      http.return_code(r, status)
    }
  }
}

/// Canonical Milestone 3 async policy shell: one decision flow over JWT + OIDC
/// identity, query extraction, phase-safe WAF / nftset facts, optional session
/// identity, and a remote OPA step. Emits structured X-Authz-* headers so
/// auth_request callers or response modules can consume the decision context.
fn enriched_milestone3_check(r: HTTPRequest) -> Promise(Nil) {
  let endpoint = case http.get_variable(r, "authz_opa_url") {
    Ok(v) -> v
    Error(_) -> ""
  }
  let security_facts = security.from_request(r)
  let base_identity =
    identity.with_jwt_and_oidc(r, ["role", "sub"], ["sub", "email", "name"])
  case session_subject_claim(r) {
    Error(decision) -> {
      let ctx = Context(..base_identity, query: query.from_request(r, ["view"]))
      let _ = enrich.inject_claims(r, ctx)
      let _ =
        enrich.inject_facts(
          r,
          facts.compose(ctx, decision, security_facts, None),
        )
      apply_decision(r, decision, "authz: milestone3 denied — ")
    }
    Ok(subject) -> {
      let merged_claims = case subject {
        None -> base_identity.claims
        Some(value) ->
          dict.insert(base_identity.claims, "session_subject", value)
      }
      let ctx =
        Context(
          ..base_identity,
          claims: merged_claims,
          query: query.from_request(r, ["view"]),
        )
      let rules = [
        policy.to_async(policy.method_in(["GET"])),
        policy.to_async(policy.claim_present("sub")),
        policy.to_async(policy.claim_present("email")),
        policy.to_async(
          policy.claim_contains_one_of("role", ["admin", "support"]),
        ),
        policy.to_async(policy.query_param_one_of("view", ["summary", "full"])),
        policy.to_async(policy.claim_present("session_subject")),
        policy.to_async(security.pass_rule(r)),
        fn(ctx) { remote.opa_allow(ctx, endpoint, 2000) },
      ]
      use decision <- promise.await(policy.async_evaluate(ctx, rules))
      let _ = enrich.inject_claims(r, ctx)
      let _ =
        enrich.inject_facts(
          r,
          facts.compose(ctx, decision, security_facts, subject),
        )
      apply_decision(r, decision, "authz: milestone3 denied — ")
    }
  }
}

/// Allow-path WAF check: reads $waf_result and passes the request if the WAF
/// result is "allowed" or "dryrun". Returns 204 on pass, 403 on deny.
/// Does not reconstruct WAF deny decisions from error_page redirects.
fn waf_check(r: HTTPRequest) -> Nil {
  let fact = security.waf_from_request(r)
  case security.waf_pass(fact) {
    Allow -> http.return_code(r, 204)
    Deny(status, reason) -> {
      let _ = http.log(r, "authz: " <> reason)
      http.return_code(r, status)
    }
  }
}

/// Like waf_check but also injects WAF facts as response headers
/// (X-Authz-Waf-Result, X-Authz-Waf-Score, X-Authz-Waf-Category,
/// X-Authz-Waf-Rule-Id). Use with auth_request so downstream locations
/// can observe WAF signals without re-reading native variables.
fn enriched_waf_check(r: HTTPRequest) -> Nil {
  let fact = security.waf_from_request(r)
  let _ = enrich.inject_waf_facts(r, fact)
  case security.waf_pass(fact) {
    Allow -> http.return_code(r, 204)
    Deny(status, reason) -> {
      let _ = http.log(r, "authz: " <> reason)
      http.return_code(r, status)
    }
  }
}

/// Allow-path nftset check: reads $nftset_result and passes the request if the
/// nftset result is "allow" or not set. Returns 204 on pass, 403 on deny.
fn nftset_check(r: HTTPRequest) -> Nil {
  let fact = security.nftset_from_request(r)
  case security.nftset_pass(fact) {
    Allow -> http.return_code(r, 204)
    Deny(status, reason) -> {
      let _ = http.log(r, "authz: " <> reason)
      http.return_code(r, status)
    }
  }
}

/// Verify a session cookie and forward the session subject to the upstream.
/// Reads $session_dict from nginx variables. Designed for use with nginx
/// auth_request — returns 204 + X-Session-Subject on success, 401 otherwise.
fn session_gate(r: HTTPRequest) -> Nil {
  let dict_name = case http.get_variable(r, "session_dict") {
    Ok(v) -> v
    Error(_) -> ""
  }
  let descriptor = session_model.default_descriptor()
  case http.get_header_in(r, "cookie") {
    Error(_) -> http.return_code(r, 401)
    Ok(cookie_header) ->
      case session_cookie.read_id(cookie_header, descriptor.cookie.name) {
        Error(_) -> http.return_code(r, 401)
        Ok(sid) ->
          case dict_name {
            "" -> http.return_code(r, 503)
            dict ->
              case session_store.load(dict, sid) {
                Error(_) -> http.return_code(r, 401)
                Ok(subject) -> {
                  let _ = http.set_headers_out(r, "X-Session-Subject", subject)
                  http.return_code(r, 204)
                }
              }
          }
      }
  }
}

/// js_access — access-phase equivalent of `check`. On allow: returns without
/// calling anything so nginx advances to the content phase (proxy_pass, etc.).
/// On deny: calls r.return(status) immediately before content phase runs.
/// Use over auth_request when no subrequest round-trip is needed.
fn access_check(r: HTTPRequest) -> Nil {
  let ctx = context_from_request(r)
  let rules = [
    policy.method_in(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]),
  ]
  case policy.evaluate(ctx, rules) {
    Allow -> Nil
    Deny(status, reason) -> {
      let _ = http.log(r, "authz: access denied — " <> reason)
      http.return_code(r, status)
    }
  }
}

/// js_access — reads JSON body, extracts named fields, then applies a
/// body-param policy. Reads $authz_body_fields (comma-separated list of
/// field names to extract) and $authz_body_required (required field name).
/// On allow: passes to content handler. On deny: returns 4xx immediately.
fn access_json_check(r: HTTPRequest) -> Promise(Nil) {
  case configured_body_policy(r, "json") {
    None -> promise.resolve(Nil)
    Some(#(field_names, required)) ->
      http.read_request_json(r)
      |> promise.await(fn(json_obj) {
        let body_dict = body.from_json(json_obj, field_names)
        let ctx = Context(..context_from_request(r), body: body_dict)
        policy.evaluate(ctx, [policy.body_param_present(required)])
        |> apply_access_decision(r, _, "authz: access json denied — ")
      })
      |> promise.rescue(fn(error) {
        let _ =
          http.log(
            r,
            "authz: access json read failed — " <> string.inspect(error),
          )
        http.return_code(r, 400)
        Nil
      })
  }
}

/// js_access — reads form body (application/x-www-form-urlencoded), extracts
/// named fields, then applies a body-param policy. Reads $authz_body_fields
/// (comma-separated field names) and $authz_body_required (required field).
fn access_form_check(r: HTTPRequest) -> Promise(Nil) {
  case configured_body_policy(r, "form") {
    None -> promise.resolve(Nil)
    Some(#(field_names, required)) ->
      http.read_request_form(r)
      |> promise.await(fn(form) {
        let body_dict = body.from_form(form, field_names)
        let ctx = Context(..context_from_request(r), body: body_dict)
        policy.evaluate(ctx, [policy.body_param_present(required)])
        |> apply_access_decision(r, _, "authz: access form denied — ")
      })
      |> promise.rescue(fn(error) {
        let _ =
          http.log(
            r,
            "authz: access form read failed — " <> string.inspect(error),
          )
        http.return_code(r, 400)
        Nil
      })
  }
}

fn ok_response(r: HTTPRequest) -> Nil {
  http.return_text(r, 200, "ok")
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("check", check)
  |> ngx.merge("jwt_check", jwt_check)
  |> ngx.merge("remote_check", remote_check)
  |> ngx.merge("cached_remote_check", cached_remote_check)
  |> ngx.merge("enriched_check", enriched_check)
  |> ngx.merge("enriched_jwt_check", enriched_jwt_check)
  |> ngx.merge("enriched_remote_check", enriched_remote_check)
  |> ngx.merge("session_gate", session_gate)
  |> ngx.merge("oidc_check", oidc_check)
  |> ngx.merge("enriched_oidc_check", enriched_oidc_check)
  |> ngx.merge("enriched_composed_check", enriched_composed_check)
  |> ngx.merge("enriched_milestone3_check", enriched_milestone3_check)
  |> ngx.merge("waf_check", waf_check)
  |> ngx.merge("enriched_waf_check", enriched_waf_check)
  |> ngx.merge("nftset_check", nftset_check)
  |> ngx.merge("access_check", access_check)
  |> ngx.merge("access_json_check", access_json_check)
  |> ngx.merge("access_form_check", access_form_check)
  |> ngx.merge("ok_response", ok_response)
}
