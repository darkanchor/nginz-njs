import feature_flags/evaluation.{type Flag, Flag}
import gleam/int
import gleam/result
import gleam/string
import mlcache/lookup as mc_lookup
import mlcache/model as mc_model
import mlcache/shared as mc_shared

/// Load flag config from a named shared dict. Returns Error(Nil) on Miss
/// so callers can fall back to nginx variables.
pub fn load(dict_name: String, flag_name: String) -> Result(Flag, Nil) {
  mc_shared.get(dict_name, flag_name, 0)
  |> mc_lookup.get_value
  |> result.try(decode_flag(flag_name, _))
}

/// Persist flag config to a named shared dict with the given TTL in seconds.
pub fn save(dict_name: String, flag: Flag, ttl_s: Int) -> Nil {
  let config =
    mc_model.CacheConfig(
      backend: mc_model.SharedDict,
      refresh_policy: mc_model.RefreshOnMiss,
      ttl_seconds: ttl_s,
      stale_ttl_seconds: 0,
    )
  mc_shared.put(dict_name, flag.name, encode_flag(flag), config)
}

fn encode_flag(flag: Flag) -> String {
  let e = case flag.enabled {
    True -> "1"
    False -> "0"
  }
  e <> ":" <> int.to_string(flag.rollout_pct)
}

fn decode_flag(name: String, raw: String) -> Result(Flag, Nil) {
  case string.split_once(raw, ":") {
    Error(_) -> Error(Nil)
    Ok(#(enabled_str, pct_str)) ->
      case int.parse(pct_str) {
        Error(_) -> Error(Nil)
        Ok(pct) ->
          Ok(Flag(name: name, enabled: enabled_str == "1", rollout_pct: pct))
      }
  }
}
