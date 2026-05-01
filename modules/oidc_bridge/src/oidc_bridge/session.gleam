//// OIDC session binding. Creates or updates session state on OIDC callback,
//// binding OIDC claims to the session subject for downstream consumption.
//// with a generated session ID. Full async session creation via session/store
//// is deferred to Phase 2.

import gleam/int
import oidc_bridge/model.{
  type OidcIdentity, type SessionBinding, bind, identity_summary,
}

/// Create a session binding for an OIDC identity. Returns a SessionBinding
pub fn create_binding(identity: OidcIdentity, now: Int) -> SessionBinding {
  // Generate a simple session ID from the OIDC sub and timestamp.
  // Full implementation will use session/model for proper ID generation.
  let session_id = "oidc:" <> identity.sub <> ":" <> int.to_string(now)
  bind(session_id, identity, now)
}

/// Extract the session subject from an OIDC identity for use in authz policies.
pub fn session_subject(identity: OidcIdentity) -> String {
  identity.sub
}

/// Summary of a session binding for logging.
pub fn binding_summary(binding: SessionBinding) -> String {
  "session=" <> binding.session_id <> " " <> identity_summary(binding.identity)
}
