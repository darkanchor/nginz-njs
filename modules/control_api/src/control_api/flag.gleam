import control_api/response
import feature_flags/evaluation.{type Flag, Flag}
import feature_flags/state
import gleam/int

/// Inspect a feature flag from the named shared dict.
/// Returns a JSON object with the flag's current state, or an error if absent.
pub fn inspect(dict_name: String, flag_name: String) -> String {
  case state.load(dict_name, flag_name) {
    Error(_) -> response.json_error("flag not found: " <> flag_name)
    Ok(flag) -> response.json_ok(flag_to_fields(flag))
  }
}

/// Write a feature flag to the named shared dict with the given TTL (seconds).
/// On success returns the updated flag state as JSON.
pub fn toggle(
  dict_name: String,
  flag_name: String,
  enabled: Bool,
  rollout_pct: Int,
  ttl_s: Int,
) -> String {
  let flag = Flag(name: flag_name, enabled: enabled, rollout_pct: rollout_pct)
  state.save(dict_name, flag, ttl_s)
  response.json_ok([#("action", "set"), ..flag_to_fields(flag)])
}

fn flag_to_fields(flag: Flag) -> List(#(String, String)) {
  [
    #("name", flag.name),
    #("enabled", case flag.enabled {
      True -> "true"
      False -> "false"
    }),
    #("rollout_pct", int.to_string(flag.rollout_pct)),
  ]
}
