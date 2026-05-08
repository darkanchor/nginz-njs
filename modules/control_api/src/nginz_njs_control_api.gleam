import control_api/flag
import control_api/metrics_handler
import control_api/probe
import control_api/response
import control_api/router
import control_api/session_probe
import gleam/int
import metrics/line
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn describe(r: HTTPRequest) -> Nil {
  router.describe_routes()
  |> http.return_text(r, 200, _)
}

fn health(r: HTTPRequest) -> Nil {
  response.json_ok([#("service", "control_api")])
  |> json_response(r, 200, _)
}

fn system_info_handler(r: HTTPRequest) -> Nil {
  probe.system_info()
  |> json_response(r, 200, _)
}

/// Inspect a feature flag from the named shared dict.
/// Reads ?dict=<dict_name>&name=<flag_name> from the request.
fn inspect_flag(r: HTTPRequest) -> Nil {
  let dict_name = read_var(r, "arg_dict", "feature_flags")
  let flag_name = read_var(r, "arg_name", "")
  case flag_name {
    "" ->
      response.json_error("missing required query param: name")
      |> json_response(r, 400, _)
    name ->
      flag.inspect(dict_name, name)
      |> json_response(r, 200, _)
  }
}

/// Set a feature flag in the named shared dict.
/// Reads ?dict=<dict_name>&name=<flag>&enabled=<1|0>&pct=<0-100>&ttl=<seconds>.
fn toggle_flag(r: HTTPRequest) -> Nil {
  let dict_name = read_var(r, "arg_dict", "feature_flags")
  let flag_name = read_var(r, "arg_name", "")
  let enabled = read_var(r, "arg_enabled", "1") == "1"
  let pct = case int.parse(read_var(r, "arg_pct", "100")) {
    Ok(n) -> n
    Error(_) -> 100
  }
  let ttl = case int.parse(read_var(r, "arg_ttl", "3600")) {
    Ok(n) -> n
    Error(_) -> 3600
  }
  case flag_name {
    "" ->
      response.json_error("missing required query param: name")
      |> json_response(r, 400, _)
    name ->
      flag.toggle(dict_name, name, enabled, pct, ttl)
      |> json_response(r, 200, _)
  }
}

/// Probe whether a named mlcache shared dict is reachable.
/// Reads ?dict=<dict_name> from the request.
fn probe_cache(r: HTTPRequest) -> Nil {
  let dict_name = read_var(r, "arg_dict", "")
  case dict_name {
    "" ->
      response.json_error("missing required query param: dict")
      |> json_response(r, 400, _)
    name ->
      probe.cache_probe(name)
      |> json_response(r, 200, _)
  }
}

/// Probe whether a named session shared dict is reachable.
/// Reads ?dict=<dict_name> from the request.
fn probe_session(r: HTTPRequest) -> Nil {
  let dict_name = read_var(r, "arg_dict", "")
  case dict_name {
    "" ->
      response.json_error("missing required query param: dict")
      |> json_response(r, 400, _)
    name ->
      session_probe.session_probe(name)
      |> json_response(r, 200, _)
  }
}

/// Render a StatsD line from query params using the shared metrics module.
/// Supported params: ?name=&value=&type=&ns=&rate=&tags=
fn render_metric(r: HTTPRequest) -> Nil {
  case
    metrics_handler.render_metric(
      read_var(r, "arg_name", "control_api_metric"),
      read_var(r, "arg_value", "1"),
      read_var(r, "arg_type", "c"),
      read_var(r, "arg_ns", "nginz"),
      read_var(r, "arg_rate", "1.0"),
      read_var(r, "arg_tags", ""),
    )
  {
    Ok(line) -> http.return_text(r, 200, line)
    Error(err) -> http.return_text(r, 400, line.describe_error(err))
  }
}

/// Return a human-readable description of a metric built from query params.
fn describe_metric(r: HTTPRequest) -> Nil {
  case
    metrics_handler.describe_metric(
      read_var(r, "arg_name", "control_api_metric"),
      read_var(r, "arg_value", "1"),
      read_var(r, "arg_type", "c"),
      read_var(r, "arg_ns", "nginz"),
      read_var(r, "arg_rate", "1.0"),
      read_var(r, "arg_tags", ""),
    )
  {
    Ok(text) -> http.return_text(r, 200, text)
    Error(err) -> http.return_text(r, 400, line.describe_error(err))
  }
}

fn read_var(r: HTTPRequest, name: String, default: String) -> String {
  case http.get_variable(r, name) {
    Ok(v) if v != "" -> v
    _ -> default
  }
}

fn json_response(r: HTTPRequest, status: Int, body: String) -> Nil {
  let _ = http.set_headers_out(r, "Content-Type", "application/json")
  http.return_text(r, status, body)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
  |> ngx.merge("health", health)
  |> ngx.merge("system_info", system_info_handler)
  |> ngx.merge("inspect_flag", inspect_flag)
  |> ngx.merge("toggle_flag", toggle_flag)
  |> ngx.merge("probe_cache", probe_cache)
  |> ngx.merge("probe_session", probe_session)
  |> ngx.merge("render_metric", render_metric)
  |> ngx.merge("describe_metric", describe_metric)
}
