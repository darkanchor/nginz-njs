import authz/cache.{Hit, Miss}
import authz/claims
import authz/enrich
import authz/policy.{type Context, type Decision, Allow, Context, Deny}
import authz/remote
import gleam/dict
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/string
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn context_from_request(r: HTTPRequest) -> Context {
  Context(
    method: http.method(r),
    path: http.uri(r),
    remote_addr: http.remote_address(r),
    headers: http.headers_in(r),
    claims: dict.new(),
    query: dict.new(),
  )
}

fn check(r: HTTPRequest) -> Nil {
  let ctx = context_from_request(r)
  let rules = [
    policy.method_in(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]),
  ]
  case policy.evaluate(ctx, rules) {
    Allow -> http.return_code(r, 204)
    Deny(reason) -> {
      let _ = http.log(r, "authz: denied — " <> reason)
      http.return_code(r, 403)
    }
  }
}

fn jwt_check(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let ctx =
    Context(..context_from_request(r), claims: claims.from_vars(vars, ["role"]))
  let rules = [
    policy.any_of([
      policy.has_claim("role", "admin"),
      policy.has_claim("role", "user"),
    ]),
  ]
  case policy.evaluate(ctx, rules) {
    Allow -> http.return_code(r, 204)
    Deny(reason) -> {
      let _ = http.log(r, "authz: jwt denied — " <> reason)
      http.return_code(r, 403)
    }
  }
}

fn remote_check(r: HTTPRequest) -> Promise(Nil) {
  let vars = http.get_variables(r)
  let endpoint = case ngx.get(vars, "authz_opa_url") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let ctx = context_from_request(r)
  use decision <- promise.await(remote.opa_allow(ctx, endpoint, 2000))
  case decision {
    Allow -> {
      http.return_code(r, 204)
      promise.resolve(Nil)
    }
    Deny(reason) -> {
      let _ = http.log(r, "authz: remote denied — " <> reason)
      http.return_code(r, 403)
      promise.resolve(Nil)
    }
  }
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
    Deny(reason) -> {
      let _ = http.log(r, log_prefix <> reason)
      http.return_code(r, 403)
      promise.resolve(Nil)
    }
  }
}

/// Like remote_check but caches decisions in the `authz_cache` shared dict
/// keyed by a SHA-256 of the Bearer token. Reads $authz_cache_ttl (seconds,
/// default 300) and $authz_opa_url from nginx variables.
fn cached_remote_check(r: HTTPRequest) -> Promise(Nil) {
  let vars = http.get_variables(r)
  let endpoint = case ngx.get(vars, "authz_opa_url") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let ttl = case ngx.get(vars, "authz_cache_ttl") {
    Ok(v) ->
      case int.parse(ngx.to_string(v)) {
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
    Deny(reason) -> {
      let _ = http.log(r, "authz: denied — " <> reason)
      http.return_code(r, 403)
    }
  }
}

/// Like jwt_check but also injects X-Authz-Status and X-Authz-<Claim> headers
/// so upstreams receive the role without re-reading JWT variables.
fn enriched_jwt_check(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let ctx =
    Context(
      ..context_from_request(r),
      claims: claims.from_vars(vars, ["role", "sub"]),
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
    Deny(reason) -> {
      let _ = http.log(r, "authz: jwt denied — " <> reason)
      http.return_code(r, 403)
    }
  }
}

/// Like remote_check but injects X-Authz-Status after the OPA decision.
fn enriched_remote_check(r: HTTPRequest) -> Promise(Nil) {
  let vars = http.get_variables(r)
  let endpoint = case ngx.get(vars, "authz_opa_url") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let ctx = context_from_request(r)
  use decision <- promise.await(remote.opa_allow(ctx, endpoint, 2000))
  let _ = enrich.inject_status(r, decision)
  case decision {
    Allow -> {
      http.return_code(r, 204)
      promise.resolve(Nil)
    }
    Deny(reason) -> {
      let _ = http.log(r, "authz: remote denied — " <> reason)
      http.return_code(r, 403)
      promise.resolve(Nil)
    }
  }
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
}
