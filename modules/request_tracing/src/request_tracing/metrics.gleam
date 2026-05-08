//// Metrics adapter for request tracing. Emits latency and span counters
//// to the metrics module.

import metrics/helpers
import metrics/line.{type Metric, Tag}
import request_tracing/model.{type TraceContext}

/// Histogram-style latency metric for the full request.
pub fn latency_metric(
  ctx: TraceContext,
  duration_ms: Int,
  route: String,
) -> Metric {
  helpers.latency("request_trace_duration_ms", duration_ms, [
    Tag(name: "route", value: route),
    Tag(name: "request_id", value: ctx.request_id),
  ])
}

/// Counter for traced requests.
pub fn traced_counter(_ctx: TraceContext, route: String) -> Metric {
  helpers.increment("request_trace_total", [
    Tag(name: "route", value: route),
  ])
}
