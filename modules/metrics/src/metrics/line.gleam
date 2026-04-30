import gleam/int
import gleam/list
import gleam/string

pub type MetricType {
  Counter
  Gauge
  Timing
}

pub type Tag {
  Tag(name: String, value: String)
}

pub type Metric {
  Metric(name: String, value: Int, metric_type: MetricType, tags: List(Tag))
}

pub fn demo_metric() -> Metric {
  Metric(name: "requests_total", value: 1, metric_type: Counter, tags: [
    Tag(name: "route", value: "demo"),
    Tag(name: "status", value: "200"),
  ])
}

fn metric_type_text(metric_type: MetricType) -> String {
  case metric_type {
    Counter -> "c"
    Gauge -> "g"
    Timing -> "ms"
  }
}

fn tag_text(tag: Tag) -> String {
  tag.name <> ":" <> tag.value
}

pub fn render_statsd(metric: Metric) -> String {
  let tags = metric.tags |> list.map(tag_text) |> string.join(",")
  metric.name
  <> ":"
  <> int.to_string(metric.value)
  <> "|"
  <> metric_type_text(metric.metric_type)
  <> "|#"
  <> tags
}

pub fn describe(metric: Metric) -> String {
  metric.name <> " type=" <> metric_type_text(metric.metric_type)
}
