//// Cache-aware step composition for workflow pipelines.
////
//// Wraps a `Step` with mlcache read-through or stale-while-refresh semantics.
//// On a cache hit the step is skipped entirely. On a miss the step runs and
//// the result is written to the cache. `stale_while_refresh` also serves a
//// stale value immediately while triggering a refresh for the next request.
////
//// The cache key is caller-supplied so the same step can be cached under
//// different keys (e.g. per-token, per-path, per-user).

import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/string
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
      Hit(cached) -> promise.resolve(decode_cached_result(cached))
      _ -> {
        use result <- promise.await(step(r))
        case result {
          Fetched(status, body) -> {
            mc_shared.put(
              dict_name,
              key,
              encode_cached_result(status, body),
              cache_config(ttl_s, 0),
            )
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
      Hit(cached) -> promise.resolve(decode_cached_result(cached))
      Stale(cached) -> {
        let stale_result = promise.resolve(decode_cached_result(cached))
        // Run refresh but discard the result — the next caller sees fresh data.
        let _ =
          promise.await(step(r), fn(result) {
            case result {
              Fetched(status, fresh_body) ->
                mc_shared.put(
                  dict_name,
                  key,
                  encode_cached_result(status, fresh_body),
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
          Fetched(status, body) ->
            mc_shared.put(
              dict_name,
              key,
              encode_cached_result(status, body),
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

fn encode_cached_result(status: Int, body: String) -> String {
  int.to_string(status) <> ":" <> body
}

fn decode_cached_result(cached: String) -> StepResult {
  case string.split_once(cached, ":") {
    Error(_) -> Failed("invalid cached workflow entry")
    Ok(#(status_str, body)) ->
      case int.parse(status_str) {
        Ok(status) -> Fetched(status, body)
        Error(_) -> Failed("invalid cached workflow status")
      }
  }
}
