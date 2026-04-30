import gleam/int
import gleam/result

pub type Backend {
  SharedDict
  PerWorkerOnly
}

pub type RefreshPolicy {
  RefreshOnMiss
  RefreshStale
}

pub type CacheConfig {
  CacheConfig(
    backend: Backend,
    refresh_policy: RefreshPolicy,
    ttl_seconds: Int,
    stale_ttl_seconds: Int,
  )
}

pub type LookupResult {
  Hit(value: String)
  Miss
  Stale(value: String)
}

pub type ConfigError {
  TtlNotPositive
  StaleTtlNegative
  StaleWithNoWindow
}

pub fn default_config() -> CacheConfig {
  CacheConfig(
    backend: SharedDict,
    refresh_policy: RefreshOnMiss,
    ttl_seconds: 60,
    stale_ttl_seconds: 0,
  )
}

pub fn validate(config: CacheConfig) -> Result(CacheConfig, ConfigError) {
  use _ <- result.try(case config.ttl_seconds > 0 {
    True -> Ok(Nil)
    False -> Error(TtlNotPositive)
  })
  use _ <- result.try(case config.stale_ttl_seconds >= 0 {
    True -> Ok(Nil)
    False -> Error(StaleTtlNegative)
  })
  case config.refresh_policy {
    RefreshStale ->
      case config.stale_ttl_seconds > 0 {
        True -> Ok(config)
        False -> Error(StaleWithNoWindow)
      }
    RefreshOnMiss -> Ok(config)
  }
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
  <> " stale="
  <> int.to_string(config.stale_ttl_seconds)
}
