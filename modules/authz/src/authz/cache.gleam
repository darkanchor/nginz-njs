import authz/policy.{type Decision, Allow, Deny}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/string
import njs/buffer.{Hex, Utf8, from_string}
import njs/crypto
import njs/shared_dict.{ItemString}

pub type CacheResult {
  Hit(decision: Decision)
  Miss
}

/// Look up a cached decision for the given raw token.
/// Returns Miss when the dict is unavailable, the key is absent, or the
/// stored value is unrecognised.
pub fn lookup(dict_name: String, token: String) -> Promise(CacheResult) {
  use key <- promise.await(cache_key(token))
  case shared_dict.get_shared_dict(dict_name) {
    Error(_) -> promise.resolve(Miss)
    Ok(dict) ->
      case shared_dict.has(dict, key) {
        False -> promise.resolve(Miss)
        True ->
          promise.resolve(case shared_dict.get(dict, key) {
            ItemString("allow") -> Hit(Allow)
            ItemString(s) -> decode_deny(s)
            _ -> Miss
          })
      }
  }
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
  case shared_dict.get_shared_dict(dict_name) {
    Error(_) -> promise.resolve(Nil)
    Ok(dict) -> {
      let value = case decision {
        Allow -> ItemString("allow")
        Deny(status, reason) ->
          ItemString("deny:" <> int.to_string(status) <> ":" <> reason)
      }
      let _ = shared_dict.set(dict, key, value, ttl_s * 1000)
      promise.resolve(Nil)
    }
  }
}

fn decode_deny(s: String) -> CacheResult {
  // format: "deny:<status>:<reason>"
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
