import gleam/int
import gleam/string
import mlcache/model.{type CacheConfig, type LookupResult, Hit, Miss, Stale}
import njs/ngx
import njs/shared_dict.{ItemString}

/// Read from a named shared dict. `stale_ttl_seconds` controls whether an
/// entry past its fresh expiry is returned as Stale (> 0) or Miss (0).
/// Returns Miss when the dict is unavailable or the key is absent.
pub fn get(
  dict_name: String,
  key: String,
  stale_ttl_seconds: Int,
) -> LookupResult {
  case shared_dict.get_shared_dict(dict_name) {
    Error(_) -> Miss
    Ok(dict) ->
      case shared_dict.has(dict, key) {
        False -> Miss
        True ->
          case shared_dict.get(dict, key) {
            ItemString(s) -> decode_entry(s, stale_ttl_seconds)
            _ -> Miss
          }
      }
  }
}

/// Write a value to a named shared dict.
/// The dict TTL is set to ttl_seconds + stale_ttl_seconds so entries remain
/// readable during the stale window. The fresh expiry is embedded in the
/// stored string as a millisecond timestamp.
pub fn put(
  dict_name: String,
  key: String,
  value: String,
  config: CacheConfig,
) -> Nil {
  case shared_dict.get_shared_dict(dict_name) {
    Error(_) -> Nil
    Ok(dict) -> {
      let now_ms = ngx.now()
      let fresh_expiry_ms = now_ms + config.ttl_seconds * 1000
      let stored = int.to_string(fresh_expiry_ms) <> ":" <> value
      let dict_ttl_ms = { config.ttl_seconds + config.stale_ttl_seconds } * 1000
      let _ = shared_dict.set(dict, key, ItemString(stored), dict_ttl_ms)
      Nil
    }
  }
}

/// Attempt to acquire a per-key write lock using the atomic add semantics of
/// ngx.shared. Returns True if the lock was acquired (the caller should fetch,
/// put, then release_lock). Returns False if another worker holds the lock.
/// Degrades gracefully — returns True when the dict is unavailable so the
/// caller still proceeds.
pub fn try_lock(dict_name: String, key: String, lock_ttl_ms: Int) -> Bool {
  case shared_dict.get_shared_dict(dict_name) {
    Error(_) -> True
    Ok(dict) ->
      shared_dict.add(dict, lock_key(key), ItemString("1"), lock_ttl_ms)
  }
}

/// Release a previously acquired lock.
pub fn release_lock(dict_name: String, key: String) -> Nil {
  case shared_dict.get_shared_dict(dict_name) {
    Error(_) -> Nil
    Ok(dict) -> {
      let _ = shared_dict.delete(dict, lock_key(key))
      Nil
    }
  }
}

/// Delete a key from the named shared dict. Silent no-op when unavailable.
pub fn delete(dict_name: String, key: String) -> Nil {
  case shared_dict.get_shared_dict(dict_name) {
    Error(_) -> Nil
    Ok(dict) -> {
      let _ = shared_dict.delete(dict, key)
      Nil
    }
  }
}

fn lock_key(key: String) -> String {
  key <> ":lock"
}

fn decode_entry(stored: String, stale_ttl_seconds: Int) -> LookupResult {
  case string.split_once(stored, ":") {
    Error(_) -> Miss
    Ok(#(expiry_str, value)) ->
      case int.parse(expiry_str) {
        Error(_) -> Miss
        Ok(fresh_expiry_ms) -> {
          let now_ms = ngx.now()
          case now_ms < fresh_expiry_ms {
            True -> Hit(value)
            False ->
              case stale_ttl_seconds > 0 {
                True -> Stale(value)
                False -> Miss
              }
          }
        }
      }
  }
}
