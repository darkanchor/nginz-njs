//// Reusable constructor helpers for common metric patterns.
////
//// These are the functions other modules (http_client, workflow, authz,
//// webhook) should call when emitting instrumentation events, rather than
//// constructing `Metric` values inline or formatting protocol strings on
//// their own.

import gleam/int
import metrics/line.{
  type Metric, type Tag, Counter, Distribution, Gauge, Metric, Set, Tag, Timing,
}

/// Create a counter metric. Counters are monotonic cumulative values
/// (e.g. request counts, error counts).
///
/// `namespace` and `sample_rate` default to `"nginz"` and `1.0`.
pub fn counter(name: String, value: Int, tags: List(Tag)) -> Metric {
  Metric(
    name:,
    value:,
    metric_type: Counter,
    tags:,
    sample_rate: 1.0,
    namespace: "nginz",
  )
}

/// Create a gauge metric. Gauges represent point-in-time values
/// (e.g. in-flight connections, queue depth).
pub fn gauge(name: String, value: Int, tags: List(Tag)) -> Metric {
  Metric(
    name:,
    value:,
    metric_type: Gauge,
    tags:,
    sample_rate: 1.0,
    namespace: "nginz",
  )
}

/// Create a timing metric. Timings are milliseconds values for
/// histogram aggregation (e.g. upstream response latency).
pub fn timing(name: String, value_ms: Int, tags: List(Tag)) -> Metric {
  Metric(
    name:,
    value: value_ms,
    metric_type: Timing,
    tags:,
    sample_rate: 1.0,
    namespace: "nginz",
  )
}

/// Create a distribution metric (DogStatsD).
pub fn distribution(name: String, value: Int, tags: List(Tag)) -> Metric {
  Metric(
    name:,
    value:,
    metric_type: Distribution,
    tags:,
    sample_rate: 1.0,
    namespace: "nginz",
  )
}

/// Create a set metric. Sets count unique values (e.g. unique user IDs).
pub fn set(name: String, value: Int, tags: List(Tag)) -> Metric {
  Metric(
    name:,
    value:,
    metric_type: Set,
    tags:,
    sample_rate: 1.0,
    namespace: "nginz",
  )
}

/// Shorthand: counter incremented by 1. Useful for event-counting.
///
/// ```gleam
/// increment("http_requests_total", [tag_status(200)])
/// ```
pub fn increment(name: String, tags: List(Tag)) -> Metric {
  counter(name, 1, tags)
}

/// Shorthand: timing in milliseconds. Alias for `timing`.
///
/// ```gleam
/// latency("upstream_duration_ms", 42, [tag_route("/api/users")])
/// ```
pub fn latency(name: String, ms: Int, tags: List(Tag)) -> Metric {
  timing(name, ms, tags)
}

/// Shorthand: error counter (+1), automatically tagged with `error:true`.
///
/// ```gleam
/// error_event("upstream_failure", [tag_route("/api/users"), tag_status(502)])
/// ```
pub fn error_event(name: String, tags: List(Tag)) -> Metric {
  let error_tag = Tag(name: "error", value: "true")
  increment(name, [error_tag, ..tags])
}

// --- Tag constructors ---

/// Create a `service:<name>` tag. Use to namespace metrics by service.
pub fn tag_service(service: String) -> Tag {
  Tag(name: "service", value: service)
}

/// Create a `status:<code>` tag. Use for HTTP status codes.
pub fn tag_status(status: Int) -> Tag {
  Tag(name: "status", value: int.to_string(status))
}

/// Create a `route:<path>` tag. Use for request route patterns.
pub fn tag_route(route: String) -> Tag {
  Tag(name: "route", value: route)
}

/// Create a `method:<verb>` tag. Use for HTTP methods.
pub fn tag_method(method: String) -> Tag {
  Tag(name: "method", value: method)
}

/// Create a `result:<outcome>` tag. Use for generic result labels
/// (e.g. "success", "deny", "timeout").
pub fn tag_result(result: String) -> Tag {
  Tag(name: "result", value: result)
}
