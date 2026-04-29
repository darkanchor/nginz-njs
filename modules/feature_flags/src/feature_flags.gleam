import feature_flags/evaluation.{
  type Flag,
  ByRemoteAddr,
  ByRequestId,
  ByUserId,
  Flag,
  bucket,
  is_enabled,
}
import gleam/int
import gleam/result
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn read_flag(r: HTTPRequest, name: String) -> Flag {
  let vars = http.get_variables(r)
  let enabled = case ngx.get(vars, "ff_" <> name <> "_enabled") {
    Ok(v) -> ngx.to_string(v) == "1"
    Error(_) -> False
  }
  let rollout = case ngx.get(vars, "ff_" <> name <> "_pct") {
    Ok(v) -> result.unwrap(int.parse(ngx.to_string(v)), 0)
    Error(_) -> 0
  }
  Flag(name: name, enabled: enabled, rollout_pct: rollout)
}

fn resolve_key(r: HTTPRequest) -> evaluation.BucketKey {
  let vars = http.get_variables(r)
  let key_type = case ngx.get(vars, "ff_key_type") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let key_val = case ngx.get(vars, "ff_key") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> http.remote_address(r)
  }
  case key_type {
    "user_id" -> ByUserId(key_val)
    "remote_addr" -> ByRemoteAddr(key_val)
    _ -> ByRequestId(key_val)
  }
}

fn evaluate_handler(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let flag_name = case ngx.get(vars, "ff_name") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let flag = read_flag(r, flag_name)
  let key = resolve_key(r)
  let result = case is_enabled(flag, key) {
    True -> "1"
    False -> "0"
  }
  http.return_text(r, 200, result)
}

fn bucket_handler(r: HTTPRequest) -> Nil {
  let key = resolve_key(r)
  http.return_text(r, 200, int.to_string(bucket(key)))
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("evaluate", evaluate_handler)
  |> ngx.merge("bucket", bucket_handler)
}
