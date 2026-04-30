import authz/policy.{type Decision, Allow, Deny}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/string
import mlcache/lookup as mc_lookup
import mlcache/model as mc_model
import mlcache/shared as mc_shared
import njs/buffer.{Hex, Utf8, from_string}
import njs/crypto

pub type CacheResult {
  Hit(decision: Decision)
  Miss
}

/// Look up a cached decision for the given raw token.
/// Returns Miss when the dict is unavailable, the key is absent, or the
/// stored value is unrecognised.
pub fn lookup(dict_name: String, token: String) -> Promise(CacheResult) {
  use key <- promise.await(cache_key(token))
  let result = mc_shared.get(dict_name, key, 0) |> mc_lookup.get_value
  promise.resolve(case result {
    Ok(s) -> decode_value(s)
    Error(_) -> Miss
  })
}

/// Store a decision in the named shared dict with a TTL in seconds.
/// Silently no-ops when the dict is unavailable.
pub fn store(
  dict_name: String,
  token: String,
  decision: Decision,
  ttl_s: Int,
) -> Promise(Nil) {
  use key <- promise.await(cache_key(token))
  let config =
    mc_model.CacheConfig(
      backend: mc_model.SharedDict,
      refresh_policy: mc_model.RefreshOnMiss,
      ttl_seconds: ttl_s,
      stale_ttl_seconds: 0,
    )
  mc_shared.put(dict_name, key, encode_decision(decision), config)
  promise.resolve(Nil)
}

fn encode_decision(decision: Decision) -> String {
  case decision {
    Allow -> "allow"
    Deny(status, reason) -> "deny:" <> int.to_string(status) <> ":" <> reason
  }
}

fn decode_value(s: String) -> CacheResult {
  case s {
    "allow" -> Hit(Allow)
    _ -> decode_deny(s)
  }
}

fn decode_deny(s: String) -> CacheResult {
  case string.split_once(s, "deny:") {
    Ok(#("", rest)) ->
      case string.split_once(rest, ":") {
        Ok(#(status_str, reason)) ->
          case int.parse(status_str) {
            Ok(status) -> Hit(Deny(status, reason))
            Error(_) -> Miss
          }
        Error(_) -> Miss
      }
    _ -> Miss
  }
}

fn cache_key(token: String) -> Promise(String) {
  token
  |> from_string(Utf8)
  |> crypto.compute_hash("sha256", _, Hex)
}
