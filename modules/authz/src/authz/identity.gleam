import authz/claims
import authz/oidc
import authz/policy.{type Context, Context}
import gleam/dict
import njs/http.{type HTTPRequest}

/// Build a base Context from the request: method, path, remote_addr, headers.
/// Claims and query are empty; extend via `with_jwt`, `with_oidc`, or
/// `with_jwt_and_oidc` for identity-enriched policy evaluation.
pub fn from_request(r: HTTPRequest) -> Context {
  Context(
    method: http.method(r),
    path: http.uri(r),
    remote_addr: http.remote_address(r),
    headers: http.headers_in(r),
    claims: dict.new(),
    query: dict.new(),
  )
}

/// Build a Context with JWT claims from $jwt_claim_<name> nginx variables.
/// `claim_names` controls which claims are read (e.g. ["sub", "role", "email"]).
pub fn with_jwt(r: HTTPRequest, claim_names: List(String)) -> Context {
  Context(..from_request(r), claims: claims.from_request(r, claim_names))
}

/// Build a Context with OIDC claims from $oidc_claim_<field> nginx variables.
/// Only non-empty values are included; missing fields are silently absent.
pub fn with_oidc(r: HTTPRequest, fields: List(String)) -> Context {
  Context(..from_request(r), claims: oidc.from_request_with_fields(r, fields))
}

/// Build a Context merging both JWT and OIDC claims.
/// JWT claims take priority over OIDC claims on key collisions.
/// Use when the deployment has both the native jwt and oidc modules active.
pub fn with_jwt_and_oidc(
  r: HTTPRequest,
  jwt_names: List(String),
  oidc_fields: List(String),
) -> Context {
  let jwt = claims.from_request(r, jwt_names)
  let oidc_claims = oidc.from_request_with_fields(r, oidc_fields)
  Context(..from_request(r), claims: dict.merge(oidc_claims, jwt))
}
