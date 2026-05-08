import gleam/dict.{type Dict}
import gleam/list
import njs/http.{type HTTPRequest}

/// Identity fields normalized from $oidc_claim_* nginx variables.
/// Set by the native oidc module after successful OIDC session validation.
pub type OidcIdentity {
  OidcIdentity(sub: String, email: String, name: String)
}

/// Read OIDC claims into a dict keyed by field name.
/// Reads $oidc_claim_sub, $oidc_claim_email, $oidc_claim_name and includes
/// non-empty values. Merge with Context.claims so existing policy rules
/// (has_claim, claim_one_of, claim_present, etc.) apply to OIDC identities.
pub fn from_request(r: HTTPRequest) -> Dict(String, String) {
  from_request_with_fields(r, ["sub", "email", "name"])
}

/// Read a configurable set of OIDC claim fields from $oidc_claim_* nginx vars.
/// Only non-empty values are included. Useful for extended claim sets such as
/// groups, roles, locale, or tenant identifiers beyond the default three.
pub fn from_request_with_fields(
  r: HTTPRequest,
  fields: List(String),
) -> Dict(String, String) {
  list.fold(fields, dict.new(), fn(acc, field) {
    case http.get_variable(r, "oidc_claim_" <> field) {
      Ok(val) ->
        case val {
          "" -> acc
          _ -> dict.insert(acc, field, val)
        }
      Error(_) -> acc
    }
  })
}

/// Read a typed OidcIdentity from request variables. Missing fields are "".
pub fn identity_from_request(r: HTTPRequest) -> OidcIdentity {
  let get = fn(field) {
    case http.get_variable(r, "oidc_claim_" <> field) {
      Ok(v) -> v
      Error(_) -> ""
    }
  }
  OidcIdentity(sub: get("sub"), email: get("email"), name: get("name"))
}

/// Convert a typed OidcIdentity to a claims dict for use with policy rules.
/// Only non-empty fields are inserted, so `has_claim` / `claim_present` work
/// as presence checks on the upstream identity.
pub fn identity_to_claims(identity: OidcIdentity) -> Dict(String, String) {
  [#("sub", identity.sub), #("email", identity.email), #("name", identity.name)]
  |> list.fold(dict.new(), fn(acc, pair) {
    let #(k, v) = pair
    case v {
      "" -> acc
      _ -> dict.insert(acc, k, v)
    }
  })
}
