import feature_flags/evaluation.{type BucketKey, ByRequestId, ByUserId}
import njs/ngx.{type JsObject}

/// Map a raw claim string value to a BucketKey.
/// Non-empty values become ByUserId; empty falls back to ByRequestId(fallback).
pub fn claim_to_key(claim_value: String, fallback_id: String) -> BucketKey {
  case claim_value {
    "" -> ByRequestId(fallback_id)
    s -> ByUserId(s)
  }
}

/// Resolve a BucketKey from the OIDC subject claim.
///
/// Checks $ff_oidc_sub first (bridge variable set by admin, e.g.
/// `set $ff_oidc_sub $jwt_claim_sub`). When that is absent or empty,
/// falls back to reading $oidc_claim_sub directly — the variable set in the
/// ACCESS phase by the native oidc module. Direct access only works when the
/// oidc module is loaded; when it is not, both lookups are empty and the
/// result is ByRequestId(fallback).
pub fn from_oidc_subject(vars: JsObject, fallback: String) -> BucketKey {
  let bridge = case ngx.get(vars, "ff_oidc_sub") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  case bridge {
    "" ->
      case ngx.get(vars, "oidc_claim_sub") {
        Ok(v) -> claim_to_key(ngx.to_string(v), fallback)
        Error(_) -> ByRequestId(fallback)
      }
    s -> claim_to_key(s, fallback)
  }
}

/// Resolve a BucketKey from $ff_jwt_<claim> — a conventional bridge variable
/// for any named JWT claim.
///
/// Typical nginx config:
///   set $ff_jwt_email $jwt_claim_email;
///
pub fn from_jwt_claim(
  vars: JsObject,
  claim: String,
  fallback: String,
) -> BucketKey {
  case ngx.get(vars, "ff_jwt_" <> claim) {
    Ok(v) -> claim_to_key(ngx.to_string(v), fallback)
    Error(_) -> ByRequestId(fallback)
  }
}
