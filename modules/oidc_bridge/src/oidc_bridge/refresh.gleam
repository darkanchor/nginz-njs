//// Token refresh orchestration. Placeholder stub — full http_client-based
//// token refresh against the OIDC provider's token endpoint is deferred to
//// Phase 2.
//// Full implementation will use http_client to call the token endpoint.

import oidc_bridge/model.{type OidcIdentity}

/// Placeholder: attempt to refresh OIDC tokens. Returns the identity unchanged.
pub fn refresh(identity: OidcIdentity, _refresh_token: String) -> OidcIdentity {
  identity
}
