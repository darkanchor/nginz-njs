//// Canary-aware feature flag integration. When a request is canary-routed,
//// feature flags can evaluate differently (e.g., enable experimental features
//// for canary users).

import canary_policy/model.{
  type CanaryContext, type CanaryDecision, Canary, Stable,
}

/// A feature flag override rule: if the canary decision matches, apply the override.
pub type FlagOverride {
  FlagOverride(
    /// Which canary decision triggers this override.
    when: CanaryDecision,
    /// Flag name to override.
    flag: String,
    /// Override value.
    value: String,
  )
}

/// Check if a flag override applies for the current canary context.
pub fn check_override(
  ctx: CanaryContext,
  overrides: List(FlagOverride),
) -> Result(FlagOverride, Nil) {
  find_matching(ctx.decision, overrides)
}

fn find_matching(
  decision: CanaryDecision,
  overrides: List(FlagOverride),
) -> Result(FlagOverride, Nil) {
  case overrides {
    [] -> Error(Nil)
    [ov, ..rest] ->
      case ov.when == decision {
        True -> Ok(ov)
        False -> find_matching(decision, rest)
      }
  }
}

/// Build a flag override for canary requests.
pub fn canary_flag(flag: String, value: String) -> FlagOverride {
  FlagOverride(when: Canary, flag: flag, value: value)
}

/// Build a flag override for stable requests.
pub fn stable_flag(flag: String, value: String) -> FlagOverride {
  FlagOverride(when: Stable, flag: flag, value: value)
}
