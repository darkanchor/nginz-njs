//// OIDC claim mapping. Maps OIDC identity claims to authz claims dict
//// for direct consumption by the authz policy engine.
//// The returned list of (key, value) pairs uses the same shape as
//// authz/claims.from_vars, so authz policies can consume it directly.

import gleam/list
import gleam/option.{type Option, None, Some}
import oidc_bridge/model.{type OidcIdentity}

/// Map an OIDC identity to an authz-compatible claims dict.
pub fn to_authz_claims(identity: OidcIdentity) -> List(#(String, String)) {
  [
    #("sub", identity.sub),
    #("email", identity.email),
    #("name", identity.name),
    ..identity.raw_claims
  ]
}

/// Check if a claim is present in the OIDC identity.
pub fn has_claim(identity: OidcIdentity, claim: String) -> Bool {
  let claims = [
    #("sub", identity.sub),
    #("email", identity.email),
    #("name", identity.name),
  ]
  case list.find(claims, fn(c) { c.0 == claim }) {
    Ok(_) -> True
    Error(_) -> list.any(identity.raw_claims, fn(c) { c.0 == claim })
  }
}

/// Get a claim value from the OIDC identity. Returns None if not present.
pub fn get_claim(identity: OidcIdentity, claim: String) -> Option(String) {
  case claim {
    "sub" -> Some(identity.sub)
    "email" -> Some(identity.email)
    "name" -> Some(identity.name)
    _ ->
      case list.find(identity.raw_claims, fn(c) { c.0 == claim }) {
        Ok(pair) -> Some(pair.1)
        Error(_) -> None
      }
  }
}
