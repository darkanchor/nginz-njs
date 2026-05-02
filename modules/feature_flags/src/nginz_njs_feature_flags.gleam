import feature_flags/canary
import feature_flags/evaluation.{
  type Flag, type Override, type VariantFlag, ByRemoteAddr, ByRequestId,
  ByUserId, Flag, Variant, VariantFlag, bucket, describe_boolean,
  describe_variant, evaluate, parse_enabled, parse_override, parse_rollout_pct,
  parse_variant_configs, select_variant,
}
import feature_flags/identity
import feature_flags/state
import gleam/int
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import session/cookie as session_cookie
import session/model as session_model
import session/store as session_store

fn read_flag_from_request(r: HTTPRequest, name: String) -> Flag {
  let enabled = case http.get_variable(r, "ff_" <> name <> "_enabled") {
    Ok(v) -> parse_enabled(v)
    Error(_) -> False
  }
  let rollout = case http.get_variable(r, "ff_" <> name <> "_pct") {
    Ok(v) -> parse_rollout_pct(v)
    Error(_) -> 0
  }
  Flag(name: name, enabled: enabled, rollout_pct: rollout)
}

fn read_flag(r: HTTPRequest, name: String) -> Flag {
  let dict_name = case http.get_variable(r, "ff_state_dict") {
    Ok(v) -> v
    Error(_) -> ""
  }
  case dict_name {
    "" -> read_flag_from_request(r, name)
    dict ->
      case state.load(dict, name) {
        Ok(flag) -> flag
        Error(_) -> read_flag_from_request(r, name)
      }
  }
}

fn read_override(r: HTTPRequest, name: String) -> Override {
  case http.get_variable(r, "ff_" <> name <> "_override") {
    Ok(v) -> parse_override(v)
    Error(_) -> evaluation.NoOverride
  }
}

fn resolve_key(r: HTTPRequest) -> evaluation.BucketKey {
  let key_type = case http.get_variable(r, "ff_key_type") {
    Ok(v) -> v
    Error(_) -> ""
  }
  let key_val = case http.get_variable(r, "ff_key") {
    Ok(v) -> v
    Error(_) -> http.remote_address(r)
  }
  case key_type {
    "user_id" -> ByUserId(key_val)
    "remote_addr" -> ByRemoteAddr(key_val)
    "session" -> resolve_session_key(r, key_val)
    "oidc_sub" -> identity.from_oidc_subject(r, key_val)
    _ -> ByRequestId(key_val)
  }
}

fn resolve_session_key(
  r: HTTPRequest,
  fallback: String,
) -> evaluation.BucketKey {
  let dict_name = case http.get_variable(r, "session_dict") {
    Ok(v) -> v
    Error(_) -> ""
  }
  case dict_name {
    "" -> ByRequestId(fallback)
    dict -> {
      let descriptor = session_model.default_descriptor()
      case http.get_header_in(r, "cookie") {
        Error(_) -> ByRequestId(fallback)
        Ok(cookie_header) ->
          case session_cookie.read_id(cookie_header, descriptor.cookie.name) {
            Error(_) -> ByRequestId(fallback)
            Ok(sid) ->
              case session_store.load(dict, sid) {
                Error(_) -> ByRequestId(fallback)
                Ok(subject) -> ByUserId(subject)
              }
          }
      }
    }
  }
}

fn evaluate_handler(r: HTTPRequest) -> Nil {
  let flag_name = case http.get_variable(r, "ff_name") {
    Ok(v) -> v
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
  let flag_name = case http.get_variable(r, "ff_name") {
    Ok(v) -> v
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
  let enabled = case http.get_variable(r, "ff_" <> name <> "_enabled") {
    Ok(v) -> parse_enabled(v)
    Error(_) -> False
  }
  let fallback_name = case http.get_variable(r, "ff_" <> name <> "_fallback") {
    Ok(v) -> v
    Error(_) -> "default"
  }
  let variants_raw = case http.get_variable(r, "ff_" <> name <> "_variants") {
    Ok(v) -> v
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
  let flag_name = case http.get_variable(r, "ff_name") {
    Ok(v) -> v
    Error(_) -> ""
  }
  let flag = read_variant_flag(r, flag_name)
  let key = resolve_key(r)
  let ov = read_override(r, flag_name)
  let selected = select_variant(flag, key, ov)
  http.return_text(r, 200, selected.name)
}

fn describe_handler(r: HTTPRequest) -> Nil {
  let flag_name = case http.get_variable(r, "ff_name") {
    Ok(v) -> v
    Error(_) -> ""
  }
  let flag = read_flag(r, flag_name)
  let key = resolve_key(r)
  let ov = read_override(r, flag_name)
  http.return_text(r, 200, describe_boolean(flag, key, ov))
}

fn describe_variant_handler(r: HTTPRequest) -> Nil {
  let flag_name = case http.get_variable(r, "ff_name") {
    Ok(v) -> v
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
  let dict_name = case http.get_variable(r, "ff_state_dict") {
    Ok(v) -> v
    Error(_) -> ""
  }
  case dict_name {
    "" -> http.return_text(r, 400, "ff_state_dict not configured")
    dict -> {
      let flag_name = case http.get_variable(r, "arg_name") {
        Ok(v) -> v
        Error(_) -> ""
      }
      case flag_name {
        "" -> http.return_text(r, 400, "name param required")
        _ -> {
          let enabled = case http.get_variable(r, "arg_enabled") {
            Ok(v) -> parse_enabled(v)
            Error(_) -> False
          }
          let rollout = case http.get_variable(r, "arg_pct") {
            Ok(v) -> parse_rollout_pct(v)
            Error(_) -> 0
          }
          let ttl_s = case http.get_variable(r, "arg_ttl") {
            Ok(v) ->
              case int.parse(v) {
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

/// Evaluate with $ngz_canary as the override source.
/// Canary requests (ngz_canary=1) always see the flag as ForceOn.
fn evaluate_canary_handler(r: HTTPRequest) -> Nil {
  let flag_name = case http.get_variable(r, "ff_name") {
    Ok(v) -> v
    Error(_) -> ""
  }
  let flag = read_flag(r, flag_name)
  let key = resolve_key(r)
  let ov = canary.canary_to_override(r)
  let decision = case evaluate(flag, key, ov) {
    True -> "1"
    False -> "0"
  }
  http.return_text(r, 200, decision)
}

/// Boolean flag decision metadata annotated with canary context.
/// Format: "flag=<name> bucket=<n> result=<0|1> canary=<0|1>"
fn describe_canary_handler(r: HTTPRequest) -> Nil {
  let flag_name = case http.get_variable(r, "ff_name") {
    Ok(v) -> v
    Error(_) -> ""
  }
  let flag = read_flag(r, flag_name)
  let key = resolve_key(r)
  let is_canary = canary.read_canary(r)
  let ov = canary.canary_flag_to_override(is_canary)
  let desc = describe_boolean(flag, key, ov)
  http.return_text(r, 200, canary.annotate_decision(desc, is_canary))
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("evaluate", evaluate_handler)
  |> ngx.merge("evaluate_js_set", evaluate_js_set)
  |> ngx.merge("evaluate_canary", evaluate_canary_handler)
  |> ngx.merge("variant", variant_handler)
  |> ngx.merge("describe", describe_handler)
  |> ngx.merge("describe_variant", describe_variant_handler)
  |> ngx.merge("describe_canary", describe_canary_handler)
  |> ngx.merge("bucket", bucket_handler)
  |> ngx.merge("set_flag", set_flag_handler)
}
