import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import metrics/line

pub fn render_metric(
  name: String,
  raw_value: String,
  raw_type: String,
  raw_namespace: String,
  raw_rate: String,
  raw_tags: String,
) -> Result(String, line.MetricError) {
  use metric <- result.try(build_metric(
    name,
    raw_value,
    raw_type,
    raw_namespace,
    raw_rate,
    raw_tags,
  ))
  Ok(line.render_statsd(metric))
}

pub fn describe_metric(
  name: String,
  raw_value: String,
  raw_type: String,
  raw_namespace: String,
  raw_rate: String,
  raw_tags: String,
) -> Result(String, line.MetricError) {
  use metric <- result.try(build_metric(
    name,
    raw_value,
    raw_type,
    raw_namespace,
    raw_rate,
    raw_tags,
  ))
  Ok(line.describe(metric))
}

fn build_metric(
  name: String,
  raw_value: String,
  raw_type: String,
  raw_namespace: String,
  raw_rate: String,
  raw_tags: String,
) -> Result(line.Metric, line.MetricError) {
  use value <- result.try(case int.parse(raw_value) {
    Ok(n) -> Ok(n)
    Error(_) -> Error(line.InvalidMetricValue(raw_value))
  })
  use metric_type <- result.try(parse_metric_type(raw_type))
  let namespace = case raw_namespace {
    "" -> "nginz"
    other -> other
  }
  use sample_rate <- result.try(case float.parse(raw_rate) {
    Ok(rate) -> Ok(rate)
    Error(_) -> Error(line.InvalidMetricValue("sample rate: " <> raw_rate))
  })
  use tags <- result.try(parse_tags(raw_tags))
  let metric =
    line.Metric(name:, value:, metric_type:, tags:, sample_rate:, namespace:)
  line.validate(metric)
}

fn parse_metric_type(raw: String) -> Result(line.MetricType, line.MetricError) {
  case raw {
    "c" | "counter" -> Ok(line.Counter)
    "g" | "gauge" -> Ok(line.Gauge)
    "ms" | "timing" -> Ok(line.Timing)
    "s" | "set" -> Ok(line.Set)
    "d" | "distribution" -> Ok(line.Distribution)
    _ -> Error(line.InvalidMetricType(raw))
  }
}

fn parse_tags(raw: String) -> Result(List(line.Tag), line.MetricError) {
  case raw {
    "" -> Ok([])
    _ ->
      raw
      |> string.split(",")
      |> list.try_map(fn(segment) {
        case string.split_once(segment, ":") {
          Ok(#(name, value)) -> Ok(line.Tag(name:, value:))
          Error(_) -> Error(line.InvalidTagFormat(segment))
        }
      })
  }
}
