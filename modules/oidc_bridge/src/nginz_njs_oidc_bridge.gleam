//// njs entry point for oidc_bridge. Reads native OIDC module variables
//// ($oidc_claim_sub, $oidc_claim_email, $oidc_claim_name), builds an
//// OidcIdentity, and provides handlers for session binding, claim mapping,
//// and token refresh.

import gleam/list
import gleam/string
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import oidc_bridge/claims
import oidc_bridge/feature_flags
import oidc_bridge/model.{type OidcIdentity, type SessionBinding}
import oidc_bridge/session

/// Bind OIDC identity to session. Returns the session binding as JSON.
fn bind_session(r: HTTPRequest) -> Nil {
  let identity = read_oidc_identity(r)
  let binding = session.create_binding(identity, ngx.now())
  let body = binding_json(binding)
  let _ = http.set_headers_out(r, "Content-Type", "application/json")
  let _ =
    http.log(
      r,
      "oidc_bridge: bind_session — " <> session.binding_summary(binding),
    )
  http.return_text(r, 200, body)
}

/// Map OIDC claims to authz-compatible claims dict. Returns claims as JSON.
fn map_claims(r: HTTPRequest) -> Nil {
  let identity = read_oidc_identity(r)
  let authz_claims = claims.to_authz_claims(identity)
  let body = claims_json(authz_claims)
  let _ = http.set_headers_out(r, "Content-Type", "application/json")
  let _ =
    http.log(
      r,
      "oidc_bridge: map_claims — " <> model.identity_summary(identity),
    )
  http.return_text(r, 200, body)
}

/// Resolve OIDC subject to feature flag key. Returns the flag key as JSON.
fn resolve_flag_key(r: HTTPRequest) -> Nil {
  let identity = read_oidc_identity(r)
  let flag_key = feature_flags.to_flag_key(identity)
  let body = "{\"flag_key\":\"" <> flag_key <> "\"}"
  let _ = http.set_headers_out(r, "Content-Type", "application/json")
  let _ = http.log(r, "oidc_bridge: resolve_flag_key — " <> flag_key)
  http.return_text(r, 200, body)
}

// --- Internal helpers ---

fn read_oidc_identity(r: HTTPRequest) -> OidcIdentity {
  let vars = http.get_variables(r)
  let sub = case ngx.get(vars, "oidc_claim_sub") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> "unknown"
  }
  let email = case ngx.get(vars, "oidc_claim_email") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let name = case ngx.get(vars, "oidc_claim_name") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  // Additional claims can be read from $oidc_claim_<name> variables.
  // For now, only the core three are supported.
  let raw_claims = []
  model.identity(sub, email, name, raw_claims)
}

fn binding_json(binding: SessionBinding) -> String {
  "{\"session_id\":\""
  <> binding.session_id
  <> "\",\"subject\":\""
  <> binding.identity.sub
  <> "\",\"email\":\""
  <> binding.identity.email
  <> "\",\"name\":\""
  <> binding.identity.name
  <> "\"}"
}

fn claims_json(claims_list: List(#(String, String))) -> String {
  let pairs =
    list.map(claims_list, fn(pair) {
      "\"" <> pair.0 <> "\":\"" <> pair.1 <> "\""
    })
  let inner = string.join(pairs, ",")
  "{" <> inner <> "}"
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("bind_session", bind_session)
  |> ngx.merge("map_claims", map_claims)
  |> ngx.merge("resolve_flag_key", resolve_flag_key)
}
