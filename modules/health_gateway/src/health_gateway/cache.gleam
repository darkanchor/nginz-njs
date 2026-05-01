//// Health cache. Caches backend health via mlcache to avoid probing on
//// every request. Placeholder stub — full mlcache integration is deferred
//// to Phase 2.
//// implementation will use mlcache/shared for stale/hit/miss semantics.

import mlcache/model as mlcache_model

/// Look up cached health status. Returns Miss (cache miss) — full
pub fn cached_health(_cache_key: String) -> mlcache_model.LookupResult {
  mlcache_model.Miss
}
