import gleam/int
import mlcache/model
import mlcache/shared
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn describe(r: HTTPRequest) -> Nil {
  model.default_config()
  |> model.summary
  |> http.return_text(r, 200, _)
}

fn put_entry(r: HTTPRequest) -> Nil {
  let key = string_var(r, "arg_key", "")
  case key {
    "" -> http.return_text(r, 400, "key required")
    _ -> {
      let value = string_var(r, "arg_value", "")
      let config =
        model.CacheConfig(
          backend: model.SharedDict,
          refresh_policy: model.RefreshOnMiss,
          ttl_seconds: int_var(r, "arg_ttl", 60),
          stale_ttl_seconds: int_var(r, "arg_stale", 0),
        )
      shared.put("cache", key, value, config)
      http.return_text(r, 200, "ok")
    }
  }
}

fn get_entry(r: HTTPRequest) -> Nil {
  let key = string_var(r, "arg_key", "")
  case key {
    "" -> http.return_text(r, 400, "key required")
    _ -> {
      let result = shared.get("cache", key, int_var(r, "arg_stale", 0))
      http.return_text(r, 200, describe_lookup(result))
    }
  }
}

fn try_lock_entry(r: HTTPRequest) -> Nil {
  let key = string_var(r, "arg_key", "")
  case key {
    "" -> http.return_text(r, 400, "key required")
    _ ->
      case shared.try_lock("cache", key, int_var(r, "arg_ttl_ms", 1000)) {
        True -> http.return_text(r, 200, "1")
        False -> http.return_text(r, 200, "0")
      }
  }
}

fn release_lock_entry(r: HTTPRequest) -> Nil {
  let key = string_var(r, "arg_key", "")
  case key {
    "" -> http.return_text(r, 400, "key required")
    _ -> {
      shared.release_lock("cache", key)
      http.return_text(r, 200, "ok")
    }
  }
}

fn describe_lookup(result: model.LookupResult) -> String {
  case result {
    model.Hit(value) -> "hit:" <> value
    model.Stale(value) -> "stale:" <> value
    model.Miss -> "miss"
  }
}

fn string_var(r: HTTPRequest, key: String, default: String) -> String {
  case http.get_variable(r, key) {
    Ok(value) -> value
    Error(_) -> default
  }
}

fn int_var(r: HTTPRequest, key: String, default: Int) -> Int {
  case http.get_variable(r, key) {
    Ok(value) ->
      case int.parse(value) {
        Ok(parsed) -> parsed
        Error(_) -> default
      }
    Error(_) -> default
  }
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
  |> ngx.merge("put_entry", put_entry)
  |> ngx.merge("get_entry", get_entry)
  |> ngx.merge("try_lock_entry", try_lock_entry)
  |> ngx.merge("release_lock_entry", release_lock_entry)
}
