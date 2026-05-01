import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import metrics/helpers
import metrics/line
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

// --- HTTP handlers ---

/// Return a human-readable summary of the demo metric.
fn describe(r: HTTPRequest) -> Nil {
  line.demo_metric()
  |> line.describe
  |> http.return_text(r, 200, _)
}

/// Return a StatsD-rendered demo metric line.
fn emit_demo(r: HTTPRequest) -> Nil {
  line.demo_metric()
  |> line.render_statsd
  |> http.return_text(r, 200, _)
}

/// Render a metric from query parameters as StatsD.
///
/// Query params: name, value (int), type (c|g|ms|s|d), ns (namespace),
/// rate (sample rate), tags (comma-separated name:value pairs).
///
/// Example: /emit?name=requests&value=1&type=c&tags=route:api,status:200
fn emit_statsd(r: HTTPRequest) -> Nil {
  case read_metric_from_args(r) {
    Ok(metric) ->
      metric
      |> line.render_statsd
      |> http.return_text(r, 200, _)
    Error(err) ->
      line.describe_error(err)
      |> http.return_text(r, 400, _)
  }
}

/// Render a metric from query parameters as DogStatsD.
fn emit_dogstatsd(r: HTTPRequest) -> Nil {
  case read_metric_from_args(r) {
    Ok(metric) ->
      metric
      |> line.render_dogstatsd
      |> http.return_text(r, 200, _)
    Error(err) ->
      line.describe_error(err)
      |> http.return_text(r, 400, _)
  }
}

/// Validate a metric built from query parameters. Returns "ok" or the
/// validation error text.
fn validate_metric(r: HTTPRequest) -> Nil {
  case read_metric_from_args(r) {
    Ok(metric) ->
      case line.validate(metric) {
        Ok(_) -> http.return_text(r, 200, "ok")
        Error(err) ->
          line.describe_error(err)
          |> http.return_text(r, 400, _)
      }
    Error(err) ->
      line.describe_error(err)
      |> http.return_text(r, 400, _)
  }
}

/// Describe a metric from query parameters.
fn describe_metric(r: HTTPRequest) -> Nil {
  case read_metric_from_args(r) {
    Ok(metric) ->
      metric
      |> line.describe
      |> http.return_text(r, 200, _)
    Error(err) ->
      line.describe_error(err)
      |> http.return_text(r, 400, _)
  }
}

/// Return a StatsD line for common instrumentation patterns.
///
/// Query params: name, pattern (counter|increment|gauge|timing|latency|error|distribution|set),
/// value (int, default 1), tags (comma-separated name:value pairs).
///
/// Example: /emit-helper?name=http_requests&pattern=increment&tags=route:api,status:200
fn emit_helper(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let name = arg_string(vars, "name", "unknown")
  let pattern = arg_string(vars, "pattern", "increment")
  let value = arg_int(vars, "value", 1)
  let tags = parse_tags(arg_string(vars, "tags", ""))

  let metric = case pattern {
    "counter" -> helpers.counter(name, value, tags)
    "increment" -> helpers.increment(name, tags)
    "gauge" -> helpers.gauge(name, value, tags)
    "timing" -> helpers.timing(name, value, tags)
    "latency" -> helpers.latency(name, value, tags)
    "error" -> helpers.error_event(name, tags)
    "distribution" -> helpers.distribution(name, value, tags)
    "set" -> helpers.set(name, value, tags)
    _ -> helpers.increment(name, tags)
  }

  metric
  |> line.render_statsd
  |> http.return_text(r, 200, _)
}

// --- Query param helpers ---

fn arg_string(vars: JsObject, key: String, default: String) -> String {
  case ngx.get(vars, "arg_" <> key) {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> default
  }
}

fn arg_int(vars: JsObject, key: String, default: Int) -> Int {
  case ngx.get(vars, "arg_" <> key) {
    Ok(v) -> result.unwrap(int.parse(ngx.to_string(v)), default)
    Error(_) -> default
  }
}

fn parse_metric_type(raw: String) -> line.MetricType {
  case raw {
    "c" | "counter" -> line.Counter
    "g" | "gauge" -> line.Gauge
    "ms" | "timing" -> line.Timing
    "s" | "set" -> line.Set
    "d" | "distribution" -> line.Distribution
    _ -> line.Counter
  }
}

fn parse_tags(raw: String) -> List(line.Tag) {
  case raw {
    "" -> []
    _ ->
      raw
      |> string.split(",")
      |> list.filter_map(fn(segment) {
        case string.split_once(segment, ":") {
          Ok(#(name, value)) -> Ok(line.Tag(name:, value:))
          Error(_) -> Error(Nil)
        }
      })
  }
}

fn read_metric_from_args(
  r: HTTPRequest,
) -> Result(line.Metric, line.MetricError) {
  let vars = http.get_variables(r)
  let name = arg_string(vars, "name", "")
  let value = arg_int(vars, "value", 0)
  let metric_type = parse_metric_type(arg_string(vars, "type", "c"))
  let namespace = arg_string(vars, "ns", "nginz")
  let rate_str = arg_string(vars, "rate", "1.0")
  let rate = case float.parse(rate_str) {
    Ok(f) -> f
    Error(_) -> 1.0
  }
  let tags = parse_tags(arg_string(vars, "tags", ""))

  let metric =
    line.Metric(
      name:,
      value:,
      metric_type:,
      tags:,
      sample_rate: rate,
      namespace:,
    )
  line.validate(metric)
}

// --- NJS exports ---

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
  |> ngx.merge("emit_demo", emit_demo)
  |> ngx.merge("emit_statsd", emit_statsd)
  |> ngx.merge("emit_dogstatsd", emit_dogstatsd)
  |> ngx.merge("validate_metric", validate_metric)
  |> ngx.merge("describe_metric", describe_metric)
  |> ngx.merge("emit_helper", emit_helper)
}
