/// Helpers for binding OIDC-derived subject identity into the session store.
///
/// The canonical pattern: after OIDC authentication the nginx admin sets
/// $session_subject from the verified subject claim before calling main.start:
///
///   set $session_subject $ff_oidc_sub;  # bridged from $jwt_claim_sub
///   js_content main.start;
///
/// Using `oidc_subject` adds a prefix that distinguishes OIDC identities from
/// other subject types (API keys, internal service accounts) when the same
/// session store is shared across multiple identity sources.
/// Normalize an OIDC subject claim into a prefixed session subject string.
/// Prefix "oidc:" ensures OIDC subjects are distinct from other identity types.
/// Returns Error(Nil) when the claim value is empty.
pub fn from_oidc_sub(sub: String) -> Result(String, Nil) {
  case sub {
    "" -> Error(Nil)
    s -> Ok("oidc:" <> s)
  }
}

/// Strip the "oidc:" prefix from a normalized session subject.
/// Returns Ok(sub) when the prefix is present, Error(Nil) otherwise.
pub fn to_oidc_sub(subject: String) -> Result(String, Nil) {
  case subject {
    "oidc:" <> sub -> Ok(sub)
    _ -> Error(Nil)
  }
}
