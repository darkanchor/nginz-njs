import mlcache/model.{
  type LookupResult, type RefreshPolicy, Hit, Miss, RefreshOnMiss, RefreshStale,
  Stale,
}

/// True only for Miss — the cache holds no value and a fetch is required.
pub fn should_fetch(result: LookupResult) -> Bool {
  case result {
    Miss -> True
    Hit(_) | Stale(_) -> False
  }
}

/// True when a refresh from the origin is needed: Miss always, Stale always.
/// Hit is fresh and requires no action.
pub fn should_refresh(result: LookupResult) -> Bool {
  case result {
    Miss | Stale(_) -> True
    Hit(_) -> False
  }
}

/// True when the cache can return a value to the caller.
/// With RefreshOnMiss, Stale is treated as a miss (no stale serving).
/// With RefreshStale, Stale is served while a background refresh runs.
pub fn can_serve(result: LookupResult, policy: RefreshPolicy) -> Bool {
  case result, policy {
    Hit(_), _ -> True
    Stale(_), RefreshStale -> True
    Stale(_), RefreshOnMiss -> False
    Miss, _ -> False
  }
}

/// Extract the cached value, returning Error(Nil) for Miss.
pub fn get_value(result: LookupResult) -> Result(String, Nil) {
  case result {
    Hit(v) | Stale(v) -> Ok(v)
    Miss -> Error(Nil)
  }
}
