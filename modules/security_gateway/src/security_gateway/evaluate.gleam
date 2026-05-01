//// Security signal evaluation. Composes multiple SecuritySignals into a
//// single SecurityDecision using the same FP patterns as `authz`:
//// all_of, any_of, not_, and pipeline composition.

import gleam/list
import security_gateway/model.{
  type SecurityDecision, type SecuritySignal, Allow, Challenge, Deny,
  IpReputation, JwtAuthenticated, OidcIdentity, RateLimit,
}

/// A rule is a function from a list of signals to a decision.
pub type Rule =
  fn(List(SecuritySignal)) -> SecurityDecision

/// Evaluate a list of rules against a set of signals. Rules are evaluated
/// left-to-right; the first non-Allow decision wins.
pub fn evaluate(
  signals: List(SecuritySignal),
  rules: List(Rule),
) -> SecurityDecision {
  list.fold_until(rules, Allow, fn(_, rule) {
    case rule(signals) {
      Allow -> list.Continue(Allow)
      decision -> list.Stop(decision)
    }
  })
}

/// All rules must return Allow.
pub fn all_of(rules: List(Rule)) -> Rule {
  fn(signals: List(SecuritySignal)) -> SecurityDecision {
    evaluate(signals, rules)
  }
}

/// At least one rule must return Allow.
pub fn any_of(rules: List(Rule)) -> Rule {
  fn(signals: List(SecuritySignal)) -> SecurityDecision {
    list.fold_until(rules, Deny(403, "no rule matched"), fn(_acc, rule) {
      case rule(signals) {
        Allow -> list.Stop(Allow)
        decision -> list.Continue(decision)
      }
    })
  }
}

/// Negate a rule: Allow becomes Deny, Deny becomes Allow.
pub fn not_(rule: Rule) -> Rule {
  fn(signals: List(SecuritySignal)) -> SecurityDecision {
    case rule(signals) {
      Allow -> Deny(403, "negated")
      Deny(_, _) -> Allow
      other -> other
    }
  }
}

// --- Pre-built signal rules ---

/// Require JWT authentication (claim sub must be present).
pub fn require_jwt() -> Rule {
  fn(signals: List(SecuritySignal)) -> SecurityDecision {
    case
      list.find(signals, fn(s) {
        case s {
          JwtAuthenticated(_) -> True
          _ -> False
        }
      })
    {
      Ok(_) -> Allow
      Error(_) -> Deny(401, "jwt required")
    }
  }
}

/// Require OIDC identity.
pub fn require_oidc() -> Rule {
  fn(signals: List(SecuritySignal)) -> SecurityDecision {
    case
      list.find(signals, fn(s) {
        case s {
          OidcIdentity(_, _, _) -> True
          _ -> False
        }
      })
    {
      Ok(_) -> Allow
      Error(_) -> Deny(401, "oidc required")
    }
  }
}

/// Require any authentication (JWT or OIDC).
pub fn require_any_auth() -> Rule {
  fn(signals: List(SecuritySignal)) -> SecurityDecision {
    let jwt_ok =
      list.any(signals, fn(s) {
        case s {
          JwtAuthenticated(_) -> True
          _ -> False
        }
      })
    let oidc_ok =
      list.any(signals, fn(s) {
        case s {
          OidcIdentity(_, _, _) -> True
          _ -> False
        }
      })
    case jwt_ok || oidc_ok {
      True -> Allow
      False -> Deny(401, "authentication required")
    }
  }
}

/// Deny if rate-limited.
pub fn deny_if_rate_limited() -> Rule {
  fn(signals: List(SecuritySignal)) -> SecurityDecision {
    case
      list.find(signals, fn(s) {
        case s {
          RateLimit(allowed: False, ..) -> True
          _ -> False
        }
      })
    {
      Ok(_) -> Deny(429, "rate limited")
      Error(_) -> Allow
    }
  }
}

/// Deny if IP is on a blocklist.
pub fn deny_if_ip_blocked() -> Rule {
  fn(signals: List(SecuritySignal)) -> SecurityDecision {
    case
      list.find(signals, fn(s) {
        case s {
          IpReputation(matched: True, ..) -> True
          _ -> False
        }
      })
    {
      Ok(_) -> Deny(403, "ip blocked")
      Error(_) -> Allow
    }
  }
}

/// Challenge if no authentication but allow authenticated.
pub fn challenge_if_anonymous() -> Rule {
  fn(signals: List(SecuritySignal)) -> SecurityDecision {
    let has_auth =
      list.any(signals, fn(s) {
        case s {
          JwtAuthenticated(_) -> True
          OidcIdentity(_, _, _) -> True
          _ -> False
        }
      })
    case has_auth {
      True -> Allow
      False -> Challenge(401, "authentication required", "login_redirect")
    }
  }
}
