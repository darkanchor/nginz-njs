import feature_flags/evaluation.{
  type Flag, type Override, type VariantFlag, ByRemoteAddr, ByRequestId,
  ByUserId, Flag, Variant, VariantFlag, bucket, describe_boolean,
  describe_variant, evaluate, parse_enabled, parse_override, parse_rollout_pct,
  parse_variant_configs, select_variant,
}
import feature_flags/state
import gleam/int
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn read_flag_from_vars(vars: JsObject, name: String) -> Flag {
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

fn read_flag(r: HTTPRequest, name: String) -> Flag {
  let vars = http.get_variables(r)
  let dict_name = case ngx.get(vars, "ff_state_dict") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  case dict_name {
    "" -> read_flag_from_vars(vars, name)
    dict ->
      case state.load(dict, name) {
        Ok(flag) -> flag
        Error(_) -> read_flag_from_vars(vars, name)
      }
  }
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
  let ov = read_override(r, flag_name)
  let decision = case evaluate(flag, key, ov) {
    True -> "1"
    False -> "0"
  }
  http.return_text(r, 200, decision)
}

fn evaluate_js_set(r: HTTPRequest) -> String {
  let vars = http.get_variables(r)
  let flag_name = case ngx.get(vars, "ff_name") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let flag = read_flag(r, flag_name)
  let key = resolve_key(r)
  let ov = read_override(r, flag_name)
  case evaluate(flag, key, ov) {
    True -> "1"
    False -> "0"
  }
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
  let ov = read_override(r, flag_name)
  let selected = select_variant(flag, key, ov)
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
  let ov = read_override(r, flag_name)
  http.return_text(r, 200, describe_boolean(flag, key, ov))
}

fn describe_variant_handler(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let flag_name = case ngx.get(vars, "ff_name") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let flag = read_variant_flag(r, flag_name)
  let key = resolve_key(r)
  let ov = read_override(r, flag_name)
  http.return_text(r, 200, describe_variant(flag, key, ov))
}

fn bucket_handler(r: HTTPRequest) -> Nil {
  let key = resolve_key(r)
  http.return_text(r, 200, int.to_string(bucket(key)))
}

/// Persist flag config to the shared dict.
/// Reads flag settings from query params: ?name=<flag>&enabled=<0|1>&pct=<0-100>[&ttl=<seconds>]
/// Requires $ff_state_dict to be set in the nginx location.
fn set_flag_handler(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let dict_name = case ngx.get(vars, "ff_state_dict") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  case dict_name {
    "" -> http.return_text(r, 400, "ff_state_dict not configured")
    dict -> {
      let flag_name = case ngx.get(vars, "arg_name") {
        Ok(v) -> ngx.to_string(v)
        Error(_) -> ""
      }
      case flag_name {
        "" -> http.return_text(r, 400, "name param required")
        _ -> {
          let enabled = case ngx.get(vars, "arg_enabled") {
            Ok(v) -> parse_enabled(ngx.to_string(v))
            Error(_) -> False
          }
          let rollout = case ngx.get(vars, "arg_pct") {
            Ok(v) -> parse_rollout_pct(ngx.to_string(v))
            Error(_) -> 0
          }
          let ttl_s = case ngx.get(vars, "arg_ttl") {
            Ok(v) ->
              case int.parse(ngx.to_string(v)) {
                Ok(t) -> t
                Error(_) -> 3600
              }
            Error(_) -> 3600
          }
          let flag =
            Flag(name: flag_name, enabled: enabled, rollout_pct: rollout)
          state.save(dict, flag, ttl_s)
          http.return_text(r, 200, "ok")
        }
      }
    }
  }
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("evaluate", evaluate_handler)
  |> ngx.merge("evaluate_js_set", evaluate_js_set)
  |> ngx.merge("variant", variant_handler)
  |> ngx.merge("describe", describe_handler)
  |> ngx.merge("describe_variant", describe_variant_handler)
  |> ngx.merge("bucket", bucket_handler)
  |> ngx.merge("set_flag", set_flag_handler)
}
