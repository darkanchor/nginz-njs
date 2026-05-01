//// Security gateway model. Represents multiple security signals (JWT claims,
//// IP reputation, rate limit, OIDC identity) and the composed allow/deny/challenge
//// decision. Same FP composition model as `authz`.

import gleam/int

/// A security signal collected from one native module.
pub type SecuritySignal {
  /// JWT claim is present and valid.
  JwtAuthenticated(claims: List(#(String, String)))
  /// JWT claim is missing or invalid.
  JwtAnonymous
  /// OIDC identity is present.
  OidcIdentity(sub: String, email: String, name: String)
  /// OIDC identity is missing.
  OidcAnonymous
  /// Rate limit decision from the native ratelimit module.
  RateLimit(allowed: Bool, key: String, source: String)
  /// IP reputation from native nftset module (future).
  IpReputation(matched: Bool, set_name: String)
  /// WAF detection (future — WAF is access-phase, no njs surface yet).
  WafDetection(blocked: Bool)
}

/// The unified security decision.
pub type SecurityDecision {
  /// Allow the request through.
  Allow
  /// Deny with a specific HTTP status and reason.
  Deny(status: Int, reason: String)
  /// Challenge the client (e.g., CAPTCHA, redirect to login).
  Challenge(status: Int, reason: String, challenge_type: String)
}

/// Build a JWT authenticated signal from claim pairs.
pub fn jwt_authenticated(claims: List(#(String, String))) -> SecuritySignal {
  JwtAuthenticated(claims: claims)
}

/// Build a JWT anonymous signal.
pub fn jwt_anonymous() -> SecuritySignal {
  JwtAnonymous
}

/// Build an OIDC identity signal.
pub fn oidc_identity(
  sub: String,
  email: String,
  name: String,
) -> SecuritySignal {
  OidcIdentity(sub: sub, email: email, name: name)
}

/// Build an OIDC anonymous signal.
pub fn oidc_anonymous() -> SecuritySignal {
  OidcAnonymous
}

/// Build a rate limit signal.
pub fn rate_limit(
  allowed: Bool,
  key: String,
  source: String,
) -> SecuritySignal {
  RateLimit(allowed: allowed, key: key, source: source)
}

/// Build an IP reputation signal (stub — nftset not yet packageable).
pub fn ip_reputation(matched: Bool, set_name: String) -> SecuritySignal {
  IpReputation(matched: matched, set_name: set_name)
}

/// Summary string for logging.
pub fn signal_summary(signal: SecuritySignal) -> String {
  case signal {
    JwtAuthenticated(_) -> "jwt:authenticated"
    JwtAnonymous -> "jwt:anonymous"
    OidcIdentity(sub: s, ..) -> "oidc:" <> s
    OidcAnonymous -> "oidc:anonymous"
    RateLimit(allowed: True, ..) -> "ratelimit:allowed"
    RateLimit(allowed: False, ..) -> "ratelimit:denied"
    IpReputation(matched: True, set_name: _) -> "ip:matched"
    IpReputation(matched: False, set_name: _) -> "ip:clean"
    WafDetection(blocked: True) -> "waf:blocked"
    WafDetection(blocked: False) -> "waf:passed"
  }
}

/// Summary string for a security decision.
pub fn decision_summary(d: SecurityDecision) -> String {
  case d {
    Allow -> "allow"
    Deny(status: s, reason: r) -> "deny " <> int.to_string(s) <> " " <> r
    Challenge(status: s, reason: r, challenge_type: ct) ->
      "challenge " <> int.to_string(s) <> " " <> ct <> " " <> r
  }
}
