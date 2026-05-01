//// OIDC bridge model. Represents OIDC identity from the native oidc module
//// and the session binding that links OIDC claims to session state.

/// An OIDC identity extracted from native module variables.
pub type OidcIdentity {
  OidcIdentity(
    /// Subject claim (unique user identifier).
    sub: String,
    /// Email claim.
    email: String,
    /// Name claim.
    name: String,
    /// Raw claims as name-value pairs for custom claim access.
    raw_claims: List(#(String, String)),
  )
}

/// A session binding — links an OIDC identity to a session ID.
pub type SessionBinding {
  SessionBinding(
    /// The session ID allocated for this identity.
    session_id: String,
    /// The OIDC identity bound to this session.
    identity: OidcIdentity,
    /// When the binding was created (epoch ms).
    created_at: Int,
  )
}

/// Build an OIDC identity from the core claims.
pub fn identity(
  sub: String,
  email: String,
  name: String,
  raw_claims: List(#(String, String)),
) -> OidcIdentity {
  OidcIdentity(sub: sub, email: email, name: name, raw_claims: raw_claims)
}

/// Build a session binding.
pub fn bind(
  session_id: String,
  identity: OidcIdentity,
  created_at: Int,
) -> SessionBinding {
  SessionBinding(
    session_id: session_id,
    identity: identity,
    created_at: created_at,
  )
}

/// Summary string for logging.
pub fn identity_summary(id: OidcIdentity) -> String {
  "sub=" <> id.sub <> " email=" <> id.email <> " name=" <> id.name
}
