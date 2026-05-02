import feature_flags/evaluation.{type Override, ForceOn, NoOverride}
import njs/http.{type HTTPRequest}
import njs/ngx

/// Map a canary boolean to an Override.
/// Canary requests become ForceOn; non-canary falls through to normal rollout.
pub fn canary_flag_to_override(is_canary: Bool) -> Override {
  case is_canary {
    True -> ForceOn
    False -> NoOverride
  }
}

/// Annotate a flag decision description with canary context.
/// Appends " canary=1" or " canary=0" to the base description string.
pub fn annotate_decision(description: String, is_canary: Bool) -> String {
  case is_canary {
    True -> description <> " canary=1"
    False -> description <> " canary=0"
  }
}

/// Read whether the current request is on the canary path.
/// Reads $ngz_canary set by the native canary module.
/// Returns False when the module is not loaded or not configured.
pub fn read_canary(r: HTTPRequest) -> Bool {
  let vars = http.get_variables(r)
  case ngx.get(vars, "ngz_canary") {
    Ok(v) -> ngx.to_string(v) == "1"
    Error(_) -> False
  }
}

/// Translate the native canary routing decision into an Override.
pub fn canary_to_override(r: HTTPRequest) -> Override {
  canary_flag_to_override(read_canary(r))
}
