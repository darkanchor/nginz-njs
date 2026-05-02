import feature_flags/evaluation.{type BucketKey, ByRequestId, ByUserId}
import njs/http.{type HTTPRequest}

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
/// Reads $ff_oidc_sub first (bridge variable set by admin when the subject is
/// already available before the content handler). When that is absent or empty,
/// falls back to reading $oidc_claim_sub directly for native oidc-gated
/// content handlers. If neither is available, the result is ByRequestId(fallback).
pub fn from_oidc_subject(r: HTTPRequest, fallback: String) -> BucketKey {
  case http.get_variable(r, "ff_oidc_sub") {
    Ok(bridged) -> {
      case bridged {
        "" ->
          case http.get_variable(r, "oidc_claim_sub") {
            Ok(native) -> claim_to_key(native, fallback)
            Error(_) -> ByRequestId(fallback)
          }
        _ -> claim_to_key(bridged, fallback)
      }
    }
    Error(_) ->
      case http.get_variable(r, "oidc_claim_sub") {
        Ok(v) -> claim_to_key(v, fallback)
        Error(_) -> ByRequestId(fallback)
      }
  }
}

/// Resolve a BucketKey from $ff_jwt_<claim> — a conventional bridge variable
/// for any named JWT claim.
///
/// Typical nginx config:
///   set $ff_jwt_email $jwt_claim_email;
///
/// This is currently a reusable library helper and is not yet wired through
/// the runtime `ff_key_type` surface in `nginz_njs_feature_flags.gleam`.
pub fn from_jwt_claim(
  r: HTTPRequest,
  claim: String,
  fallback: String,
) -> BucketKey {
  case http.get_variable(r, "ff_jwt_" <> claim) {
    Ok(v) -> claim_to_key(v, fallback)
    Error(_) -> ByRequestId(fallback)
  }
}
