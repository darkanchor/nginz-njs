import gleam/float
import gleam/int
import gleam/list
import gleam/result
import gleam/string

// --- Types ---

pub type MetricType {
  Counter
  Gauge
  Timing
  Set
  Distribution
}

pub type Tag {
  Tag(name: String, value: String)
}

pub type Metric {
  Metric(
    name: String,
    value: Int,
    metric_type: MetricType,
    tags: List(Tag),
    sample_rate: Float,
    namespace: String,
  )
}

pub type MetricError {
  EmptyName
  InvalidNameChar(String)
  EmptyTagName
  InvalidTagNameChar(String)
  InvalidTagValueChar(String)
  NegativeCounterValue
  InvalidSampleRate
  InvalidMetricType(String)
  InvalidMetricValue(String)
  InvalidTagFormat(String)
}

pub type Format {
  StatsD
  DogStatsD
}

// --- Defaults ---

pub fn default_namespace() -> String {
  "nginz"
}

pub fn default_sample_rate() -> Float {
  1.0
}

// --- Demo / example ---

pub fn demo_metric() -> Metric {
  Metric(
    name: "requests_total",
    value: 1,
    metric_type: Counter,
    tags: [
      Tag(name: "route", value: "demo"),
      Tag(name: "status", value: "200"),
    ],
    sample_rate: 1.0,
    namespace: "nginz",
  )
}

// --- Validation ---

/// Validate a Metric, returning Ok(metric) or an error describing the issue.
/// Checks: non-empty name, no illegal chars in name/tags, counter value >= 0,
/// sample rate in (0.0, 1.0].
pub fn validate(metric: Metric) -> Result(Metric, MetricError) {
  use _ <- result.try(case metric.name {
    "" -> Error(EmptyName)
    _ -> Ok(Nil)
  })
  use _ <- result.try(
    case
      string.contains(metric.name, ":")
      || string.contains(metric.name, "|")
      || string.contains(metric.name, "@")
    {
      True -> Error(InvalidNameChar(metric.name))
      False -> Ok(Nil)
    },
  )
  use _ <- result.try(case metric.metric_type {
    Counter ->
      case metric.value < 0 {
        True -> Error(NegativeCounterValue)
        False -> Ok(Nil)
      }
    _ -> Ok(Nil)
  })
  use _ <- result.try(
    case metric.sample_rate >. 0.0 && metric.sample_rate <=. 1.0 {
      True -> Ok(Nil)
      False -> Error(InvalidSampleRate)
    },
  )
  use _ <- result.try(validate_tags(metric.tags))
  Ok(metric)
}

fn validate_tags(tags: List(Tag)) -> Result(Nil, MetricError) {
  case tags {
    [] -> Ok(Nil)
    [Tag(name:, value:), ..rest] -> {
      case name {
        "" -> Error(EmptyTagName)
        _ ->
          case
            string.contains(name, ":")
            || string.contains(name, "|")
            || string.contains(name, "#")
          {
            True -> Error(InvalidTagNameChar(name))
            False ->
              case string.contains(value, "|") || string.contains(value, "#") {
                True -> Error(InvalidTagValueChar(value))
                False -> validate_tags(rest)
              }
          }
      }
    }
  }
}

/// Returns a human-readable error description.
pub fn error_text(error: MetricError) -> String {
  case error {
    EmptyName -> "metric name must not be empty"
    InvalidNameChar(name) -> "metric name contains illegal character: " <> name
    EmptyTagName -> "tag name must not be empty"
    InvalidTagNameChar(name) -> "tag name contains illegal character: " <> name
    InvalidTagValueChar(value) ->
      "tag value contains illegal character: " <> value
    NegativeCounterValue -> "counter value must be non-negative"
    InvalidSampleRate ->
      "sample rate must be > 0.0 and <= 1.0, got invalid value"
    InvalidMetricType(reason) -> "invalid metric type: " <> reason
    InvalidMetricValue(reason) -> "invalid metric value: " <> reason
    InvalidTagFormat(reason) -> "invalid tag format: " <> reason
  }
}

// --- Internal helpers ---

fn metric_type_text(metric_type: MetricType) -> String {
  case metric_type {
    Counter -> "c"
    Gauge -> "g"
    Timing -> "ms"
    Set -> "s"
    Distribution -> "d"
  }
}

fn tag_text(tag: Tag) -> String {
  tag.name <> ":" <> tag.value
}

fn sample_rate_text(rate: Float) -> String {
  case rate >=. 1.0 {
    True -> ""
    False -> "|@" <> float.to_string(rate)
  }
}

// --- Rendering ---

/// Render a Metric as a StatsD line.
///
/// Format: `<namespace>.<name>:<value>|<type>[|@<rate>]|#<tags>`
///
/// Sample rate is omitted when it equals 1.0. Tags and namespace are
/// omitted when empty.
pub fn render_statsd(metric: Metric) -> String {
  let prefix = case metric.namespace {
    "" -> metric.name
    ns -> ns <> "." <> metric.name
  }
  let tags = metric.tags |> list.map(tag_text) |> string.join(",")
  let tag_part = case tags {
    "" -> ""
    _ -> "|#" <> tags
  }
  prefix
  <> ":"
  <> int.to_string(metric.value)
  <> "|"
  <> metric_type_text(metric.metric_type)
  <> sample_rate_text(metric.sample_rate)
  <> tag_part
}

/// Render a Metric as a DogStatsD line.
///
/// DogStatsD extends StatsD with the `d` (distribution) metric type and
/// adds support for events and service checks. For standard metric types
/// the line format is identical to StatsD.
pub fn render_dogstatsd(metric: Metric) -> String {
  // DogStatsD metric line format is identical to StatsD for counter, gauge,
  // timing, set, and distribution types.
  render_statsd(metric)
}

/// Render a Metric according to the given Format.
pub fn render(metric: Metric, format: Format) -> String {
  case format {
    StatsD -> render_statsd(metric)
    DogStatsD -> render_dogstatsd(metric)
  }
}

/// Produce a human-readable summary of a Metric.
///
/// Format: `<namespace>.<name> type=<type> value=<value> rate=<rate> tags=<count>`
pub fn describe(metric: Metric) -> String {
  let prefix = case metric.namespace {
    "" -> metric.name
    ns -> ns <> "." <> metric.name
  }
  prefix
  <> " type="
  <> metric_type_text(metric.metric_type)
  <> " value="
  <> int.to_string(metric.value)
  <> " rate="
  <> float.to_string(metric.sample_rate)
  <> " tags="
  <> int.to_string(list.length(metric.tags))
}

/// Produce a summary of a validation error suitable for logging or responses.
pub fn describe_error(error: MetricError) -> String {
  "metric validation error: " <> error_text(error)
}
