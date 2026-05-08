//// Cache-aware step composition for workflow pipelines.
////
//// Wraps a `Step` with mlcache read-through or stale-while-refresh semantics.
//// On a cache hit the step is skipped entirely. On a miss the step runs and
//// the result is written to the cache. `stale_while_refresh` also serves a
//// stale value immediately while triggering a refresh for the next request.
////
//// The cache key is caller-supplied so the same step can be cached under
//// different keys (e.g. per-token, per-path, per-user).

import gleam/javascript/promise.{type Promise}
import mlcache/model.{
  type CacheConfig, CacheConfig, Hit, Miss, RefreshOnMiss, SharedDict, Stale,
}
import mlcache/shared as mc_shared
import njs/http.{type HTTPRequest}
import workflow/pipeline.{type Step, type StepResult, Failed, Fetched}

/// Wrap a step with read-through caching. On a cache hit the step is skipped
/// and the cached body is returned as `Fetched(200, body)`. On a miss the step
/// runs normally and a successful `Fetched` result is stored with `ttl_s`.
pub fn cached_step(
  step: Step,
  dict_name: String,
  key: String,
  ttl_s: Int,
) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    case mc_shared.get(dict_name, key, 0) {
      Hit(body) -> promise.resolve(Fetched(200, body))
      _ -> {
        use result <- promise.await(step(r))
        case result {
          Fetched(_, body) -> {
            mc_shared.put(dict_name, key, body, cache_config(ttl_s, 0))
            promise.resolve(result)
          }
          Failed(_) -> promise.resolve(result)
        }
      }
    }
  }
}

/// Wrap a step with stale-while-refresh semantics. On a `Hit` the step is
/// skipped. On a `Stale` hit the cached value is returned immediately for
/// this request, while the step also runs to refresh the entry for subsequent
/// requests. On a `Miss` the step blocks normally.
///
/// Use this when the step is expensive and occasional staleness is acceptable.
pub fn stale_while_refresh(
  step: Step,
  dict_name: String,
  key: String,
  ttl_s: Int,
  stale_ttl_s: Int,
) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    case mc_shared.get(dict_name, key, stale_ttl_s) {
      Hit(body) -> promise.resolve(Fetched(200, body))
      Stale(body) -> {
        let stale_result = promise.resolve(Fetched(200, body))
        // Run refresh but discard the result — the next caller sees fresh data.
        let _ =
          promise.await(step(r), fn(result) {
            case result {
              Fetched(_, fresh_body) ->
                mc_shared.put(
                  dict_name,
                  key,
                  fresh_body,
                  cache_config(ttl_s, stale_ttl_s),
                )
              Failed(_) -> Nil
            }
            promise.resolve(Nil)
          })
        stale_result
      }
      Miss -> {
        use result <- promise.await(step(r))
        case result {
          Fetched(_, body) ->
            mc_shared.put(
              dict_name,
              key,
              body,
              cache_config(ttl_s, stale_ttl_s),
            )
          Failed(_) -> Nil
        }
        promise.resolve(result)
      }
    }
  }
}

fn cache_config(ttl_s: Int, stale_ttl_s: Int) -> CacheConfig {
  CacheConfig(
    backend: SharedDict,
    refresh_policy: RefreshOnMiss,
    ttl_seconds: ttl_s,
    stale_ttl_seconds: stale_ttl_s,
  )
}
