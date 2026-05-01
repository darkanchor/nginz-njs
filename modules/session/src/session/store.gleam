import mlcache/lookup as mc_lookup
import mlcache/model as mc_model
import mlcache/shared as mc_shared

/// Load the subject for a session ID. Returns Error(Nil) on miss or expired entry.
pub fn load(dict_name: String, session_id: String) -> Result(String, Nil) {
  mc_shared.get(dict_name, session_id, 0) |> mc_lookup.get_value
}

/// Persist a session ID → subject mapping with the given TTL in seconds.
pub fn save(
  dict_name: String,
  session_id: String,
  subject: String,
  ttl_s: Int,
) -> Nil {
  let config =
    mc_model.CacheConfig(
      backend: mc_model.SharedDict,
      refresh_policy: mc_model.RefreshOnMiss,
      ttl_seconds: ttl_s,
      stale_ttl_seconds: 0,
    )
  mc_shared.put(dict_name, session_id, subject, config)
}

/// Remove a session entry. Silent no-op when the dict or key is unavailable.
pub fn delete(dict_name: String, session_id: String) -> Nil {
  mc_shared.delete(dict_name, session_id)
}
