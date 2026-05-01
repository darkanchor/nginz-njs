import metrics/helpers
import metrics/line.{type Metric}
import mlcache/model.{type LookupResult, Hit, Miss, Stale}

pub fn lookup_result(result: LookupResult) -> Metric {
  helpers.increment("mlcache_lookup_total", [
    helpers.tag_result(case result {
      Hit(_) -> "hit"
      Stale(_) -> "stale"
      Miss -> "miss"
    }),
  ])
}

pub fn lock_attempt(acquired: Bool) -> Metric {
  helpers.increment("mlcache_lock_total", [
    helpers.tag_result(case acquired {
      True -> "acquired"
      False -> "contended"
    }),
  ])
}
