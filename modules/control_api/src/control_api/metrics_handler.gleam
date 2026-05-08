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
  let value = result.unwrap(int.parse(raw_value), 1)
  let metric_type = parse_metric_type(raw_type)
  let namespace = case raw_namespace {
    "" -> "nginz"
    other -> other
  }
  let sample_rate = case float.parse(raw_rate) {
    Ok(rate) -> rate
    Error(_) -> 1.0
  }
  let metric =
    line.Metric(
      name:,
      value:,
      metric_type:,
      tags: parse_tags(raw_tags),
      sample_rate:,
      namespace:,
    )
  line.validate(metric)
}

fn parse_metric_type(raw: String) -> line.MetricType {
  case raw {
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
