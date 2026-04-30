import gleam/int

pub type Backend {
  SharedDict
  PerWorkerOnly
}

pub type RefreshPolicy {
  RefreshOnMiss
  RefreshStale
}

pub type CacheConfig {
  CacheConfig(backend: Backend, refresh_policy: RefreshPolicy, ttl_seconds: Int)
}

pub type LookupResult {
  Hit(value: String)
  Miss
  Stale(value: String)
}

pub fn default_config() -> CacheConfig {
  CacheConfig(
    backend: SharedDict,
    refresh_policy: RefreshOnMiss,
    ttl_seconds: 60,
  )
}

fn backend_text(backend: Backend) -> String {
  case backend {
    SharedDict -> "shared_dict"
    PerWorkerOnly -> "per_worker_only"
  }
}

fn refresh_policy_text(policy: RefreshPolicy) -> String {
  case policy {
    RefreshOnMiss -> "refresh_on_miss"
    RefreshStale -> "refresh_stale"
  }
}

pub fn summary(config: CacheConfig) -> String {
  backend_text(config.backend)
  <> " policy="
  <> refresh_policy_text(config.refresh_policy)
  <> " ttl="
  <> int.to_string(config.ttl_seconds)
}
