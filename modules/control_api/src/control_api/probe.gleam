import control_api/response
import gleam/int
import mlcache/model.{CacheConfig, RefreshOnMiss, SharedDict}
import mlcache/shared as mc_shared
import njs/ngx

/// Probe whether a named mlcache shared dict is reachable by writing and
/// reading a sentinel key. Returns a JSON status response.
pub fn cache_probe(dict_name: String) -> String {
  let sentinel_key = "__control_api_probe__"
  let sentinel_val = "1"
  let config =
    CacheConfig(
      backend: SharedDict,
      refresh_policy: RefreshOnMiss,
      ttl_seconds: 60,
      stale_ttl_seconds: 0,
    )
  mc_shared.put(dict_name, sentinel_key, sentinel_val, config)
  case mc_shared.get(dict_name, sentinel_key, 0) {
    model.Hit(_) ->
      response.json_ok([#("dict", dict_name), #("reachable", "true")])
    _ -> response.json_error("shared dict not reachable: " <> dict_name)
  }
}

/// Return basic runtime info: current epoch timestamp and module version.
pub fn system_info() -> String {
  response.json_ok([
    #("module", "control_api"),
    #("version", "0.1.0"),
    #("now_ms", int.to_string(ngx.now())),
  ])
}
