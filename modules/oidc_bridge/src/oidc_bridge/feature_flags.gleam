//// Feature flag integration. Resolves an OIDC subject to a ByUserId key type
//// for per-user feature flag bucketing. Composes with feature_flags/evaluation.
//// Returns the subject as "ByUserId:<sub>" for use as a feature_flags key.

import oidc_bridge/model.{type OidcIdentity}

/// Resolve an OIDC identity to a feature flag key type string.
pub fn to_flag_key(identity: OidcIdentity) -> String {
  "ByUserId:" <> identity.sub
}

/// Resolve an OIDC identity to a feature flag key type and value pair.
pub fn to_flag_key_pair(identity: OidcIdentity) -> #(String, String) {
  #("session", to_flag_key(identity))
}
