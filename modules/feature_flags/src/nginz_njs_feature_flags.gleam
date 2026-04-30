import feature_flags/evaluation.{
  type Flag, type Override, type VariantFlag, ByRemoteAddr, ByRequestId,
  ByUserId, Flag, Variant, VariantFlag, bucket, describe_boolean,
  describe_variant, evaluate, parse_enabled, parse_override, parse_rollout_pct,
  parse_variant_configs, select_variant,
}
import gleam/int
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn read_flag(r: HTTPRequest, name: String) -> Flag {
  let vars = http.get_variables(r)
  let enabled = case ngx.get(vars, "ff_" <> name <> "_enabled") {
    Ok(v) -> parse_enabled(ngx.to_string(v))
    Error(_) -> False
  }
  let rollout = case ngx.get(vars, "ff_" <> name <> "_pct") {
    Ok(v) -> parse_rollout_pct(ngx.to_string(v))
    Error(_) -> 0
  }
  Flag(name: name, enabled: enabled, rollout_pct: rollout)
}

fn read_override(r: HTTPRequest, name: String) -> Override {
  let vars = http.get_variables(r)
  case ngx.get(vars, "ff_" <> name <> "_override") {
    Ok(v) -> parse_override(ngx.to_string(v))
    Error(_) -> evaluation.NoOverride
  }
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
  let override = read_override(r, flag_name)
  let result = case evaluate(flag, key, override) {
    True -> "1"
    False -> "0"
  }
  http.return_text(r, 200, result)
}

fn evaluate_js_set(r: HTTPRequest) -> String {
  let vars = http.get_variables(r)
  let flag_name = case ngx.get(vars, "ff_name") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let flag = read_flag(r, flag_name)
  let key = resolve_key(r)
  let override = read_override(r, flag_name)
  let result = case evaluate(flag, key, override) {
    True -> "1"
    False -> "0"
  }
  result
}

fn read_variant_flag(r: HTTPRequest, name: String) -> VariantFlag {
  let vars = http.get_variables(r)
  let enabled = case ngx.get(vars, "ff_" <> name <> "_enabled") {
    Ok(v) -> parse_enabled(ngx.to_string(v))
    Error(_) -> False
  }
  let fallback_name = case ngx.get(vars, "ff_" <> name <> "_fallback") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> "default"
  }
  let variants_raw = case ngx.get(vars, "ff_" <> name <> "_variants") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  VariantFlag(
    name:,
    enabled:,
    variants: parse_variant_configs(variants_raw),
    fallback: Variant(fallback_name),
  )
}

fn variant_handler(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let flag_name = case ngx.get(vars, "ff_name") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let flag = read_variant_flag(r, flag_name)
  let key = resolve_key(r)
  let override = read_override(r, flag_name)
  let selected = select_variant(flag, key, override)
  http.return_text(r, 200, selected.name)
}

fn describe_handler(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let flag_name = case ngx.get(vars, "ff_name") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let flag = read_flag(r, flag_name)
  let key = resolve_key(r)
  let override = read_override(r, flag_name)
  http.return_text(r, 200, describe_boolean(flag, key, override))
}

fn describe_variant_handler(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let flag_name = case ngx.get(vars, "ff_name") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let flag = read_variant_flag(r, flag_name)
  let key = resolve_key(r)
  let override = read_override(r, flag_name)
  http.return_text(r, 200, describe_variant(flag, key, override))
}

fn bucket_handler(r: HTTPRequest) -> Nil {
  let key = resolve_key(r)
  http.return_text(r, 200, int.to_string(bucket(key)))
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("evaluate", evaluate_handler)
  |> ngx.merge("evaluate_js_set", evaluate_js_set)
  |> ngx.merge("variant", variant_handler)
  |> ngx.merge("describe", describe_handler)
  |> ngx.merge("describe_variant", describe_variant_handler)
  |> ngx.merge("bucket", bucket_handler)
}
