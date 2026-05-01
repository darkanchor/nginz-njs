//// Session-sticky canary assignment. Once a user is assigned to canary,
//// they stay on canary for the duration of their session. Uses the session
//// module's store for persistence.

import canary_policy/model.{
  type CanaryContext, type CanaryDecision, Canary, Stable, Unknown,
}

/// Session key used to store the canary assignment.
pub const canary_session_key = "canary_assignment"

/// Check if the session already has a canary assignment.
/// Returns the stored decision if found, or the current decision if not.
pub fn resolve_sticky(
  ctx: CanaryContext,
  stored_assignment: Result(String, Nil),
) -> CanaryDecision {
  case stored_assignment {
    Ok("canary") -> Canary
    Ok("stable") -> Stable
    _ -> ctx.decision
  }
}

/// Serialize a canary decision for storage in the session.
pub fn serialize_decision(d: CanaryDecision) -> String {
  case d {
    Canary -> "canary"
    Stable -> "stable"
    Unknown -> "stable"
  }
}

/// Deserialize a canary decision from session storage.
pub fn deserialize_decision(value: String) -> CanaryDecision {
  case value {
    "canary" -> Canary
    "stable" -> Stable
    _ -> Stable
  }
}
