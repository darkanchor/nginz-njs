import gleeunit
import gleeunit/should
import metrics/helpers
import metrics/line

pub fn main() {
  gleeunit.main()
}

// --- Model tests ---

pub fn demo_metric_has_namespace_test() {
  line.demo_metric().namespace
  |> should.equal("nginz")
}

pub fn demo_metric_sample_rate_test() {
  line.demo_metric().sample_rate
  |> should.equal(1.0)
}

// --- Rendering tests ---

pub fn render_statsd_demo_metric_test() {
  line.demo_metric()
  |> line.render_statsd
  |> should.equal("nginz.requests_total:1|c|#route:demo,status:200")
}

pub fn render_statsd_no_namespace_test() {
  let m =
    line.Metric(
      name: "req",
      value: 1,
      metric_type: line.Counter,
      tags: [],
      sample_rate: 1.0,
      namespace: "",
    )
  line.render_statsd(m)
  |> should.equal("req:1|c")
}

pub fn render_statsd_no_tags_test() {
  let m =
    line.Metric(
      name: "req",
      value: 5,
      metric_type: line.Gauge,
      tags: [],
      sample_rate: 1.0,
      namespace: "app",
    )
  line.render_statsd(m)
  |> should.equal("app.req:5|g")
}

pub fn render_statsd_with_sample_rate_test() {
  let m =
    line.Metric(
      name: "req",
      value: 1,
      metric_type: line.Counter,
      tags: [line.Tag(name: "s", value: "ok")],
      sample_rate: 0.5,
      namespace: "nginz",
    )
  line.render_statsd(m)
  |> should.equal("nginz.req:1|c|@0.5|#s:ok")
}

pub fn render_statsd_multiple_tags_test() {
  let m =
    line.Metric(
      name: "latency",
      value: 42,
      metric_type: line.Timing,
      tags: [
        line.Tag(name: "route", value: "/api"),
        line.Tag(name: "status", value: "200"),
      ],
      sample_rate: 1.0,
      namespace: "nginz",
    )
  line.render_statsd(m)
  |> should.equal("nginz.latency:42|ms|#route:/api,status:200")
}

pub fn render_dogstatsd_same_as_statsd_test() {
  // DogStatsD metric lines are identical for standard types
  let m = line.demo_metric()
  line.render_dogstatsd(m)
  |> should.equal(line.render_statsd(m))
}

pub fn render_dogstatsd_distribution_test() {
  let m =
    line.Metric(
      name: "dist",
      value: 100,
      metric_type: line.Distribution,
      tags: [],
      sample_rate: 1.0,
      namespace: "nginz",
    )
  line.render_dogstatsd(m)
  |> should.equal("nginz.dist:100|d")
}

pub fn render_format_statsd_test() {
  let m = line.demo_metric()
  line.render(m, line.StatsD)
  |> should.equal(line.render_statsd(m))
}

pub fn render_format_dogstatsd_test() {
  let m = line.demo_metric()
  line.render(m, line.DogStatsD)
  |> should.equal(line.render_dogstatsd(m))
}

// --- Describe tests ---

pub fn describe_demo_metric_test() {
  line.demo_metric()
  |> line.describe
  |> should.equal("nginz.requests_total type=c value=1 rate=1.0 tags=2")
}

pub fn describe_no_namespace_test() {
  let m =
    line.Metric(
      name: "req",
      value: 1,
      metric_type: line.Counter,
      tags: [],
      sample_rate: 1.0,
      namespace: "",
    )
  line.describe(m)
  |> should.equal("req type=c value=1 rate=1.0 tags=0")
}

// --- Validation tests ---

pub fn validate_ok_test() {
  let m = line.demo_metric()
  line.validate(m)
  |> should.be_ok()
}

pub fn validate_empty_name_test() {
  let m =
    line.Metric(
      name: "",
      value: 1,
      metric_type: line.Counter,
      tags: [],
      sample_rate: 1.0,
      namespace: "nginz",
    )
  line.validate(m)
  |> should.equal(Error(line.EmptyName))
}

pub fn validate_invalid_name_colon_test() {
  let m =
    line.Metric(
      name: "bad:name",
      value: 1,
      metric_type: line.Counter,
      tags: [],
      sample_rate: 1.0,
      namespace: "nginz",
    )
  line.validate(m)
  |> should.equal(Error(line.InvalidNameChar("bad:name")))
}

pub fn validate_invalid_name_pipe_test() {
  let m =
    line.Metric(
      name: "bad|name",
      value: 1,
      metric_type: line.Counter,
      tags: [],
      sample_rate: 1.0,
      namespace: "nginz",
    )
  line.validate(m)
  |> should.equal(Error(line.InvalidNameChar("bad|name")))
}

pub fn validate_invalid_name_at_test() {
  let m =
    line.Metric(
      name: "bad@name",
      value: 1,
      metric_type: line.Counter,
      tags: [],
      sample_rate: 1.0,
      namespace: "nginz",
    )
  line.validate(m)
  |> should.equal(Error(line.InvalidNameChar("bad@name")))
}

pub fn validate_negative_counter_test() {
  let m =
    line.Metric(
      name: "req",
      value: -1,
      metric_type: line.Counter,
      tags: [],
      sample_rate: 1.0,
      namespace: "nginz",
    )
  line.validate(m)
  |> should.equal(Error(line.NegativeCounterValue))
}

pub fn validate_negative_gauge_ok_test() {
  // Gauges can be negative
  let m =
    line.Metric(
      name: "temp",
      value: -5,
      metric_type: line.Gauge,
      tags: [],
      sample_rate: 1.0,
      namespace: "nginz",
    )
  line.validate(m)
  |> should.be_ok()
}

pub fn validate_invalid_sample_rate_zero_test() {
  let m =
    line.Metric(
      name: "req",
      value: 1,
      metric_type: line.Counter,
      tags: [],
      sample_rate: 0.0,
      namespace: "nginz",
    )
  line.validate(m)
  |> should.equal(Error(line.InvalidSampleRate))
}

pub fn validate_invalid_sample_rate_above_one_test() {
  let m =
    line.Metric(
      name: "req",
      value: 1,
      metric_type: line.Counter,
      tags: [],
      sample_rate: 1.5,
      namespace: "nginz",
    )
  line.validate(m)
  |> should.equal(Error(line.InvalidSampleRate))
}

pub fn validate_empty_tag_name_test() {
  let m =
    line.Metric(
      name: "req",
      value: 1,
      metric_type: line.Counter,
      tags: [line.Tag(name: "", value: "ok")],
      sample_rate: 1.0,
      namespace: "nginz",
    )
  line.validate(m)
  |> should.equal(Error(line.EmptyTagName))
}

pub fn validate_invalid_tag_name_test() {
  let m =
    line.Metric(
      name: "req",
      value: 1,
      metric_type: line.Counter,
      tags: [line.Tag(name: "bad:name", value: "ok")],
      sample_rate: 1.0,
      namespace: "nginz",
    )
  line.validate(m)
  |> should.equal(Error(line.InvalidTagNameChar("bad:name")))
}

pub fn validate_invalid_tag_value_test() {
  let m =
    line.Metric(
      name: "req",
      value: 1,
      metric_type: line.Counter,
      tags: [line.Tag(name: "route", value: "bad|value")],
      sample_rate: 1.0,
      namespace: "nginz",
    )
  line.validate(m)
  |> should.equal(Error(line.InvalidTagValueChar("bad|value")))
}

// --- Helper constructor tests ---

pub fn helpers_counter_test() {
  let m = helpers.counter("req", 5, [])
  m.name |> should.equal("req")
  m.value |> should.equal(5)
  m.metric_type |> should.equal(line.Counter)
  m.namespace |> should.equal("nginz")
  m.sample_rate |> should.equal(1.0)
}

pub fn helpers_increment_test() {
  let m = helpers.increment("req", [line.Tag(name: "s", value: "ok")])
  m.value |> should.equal(1)
  m.metric_type |> should.equal(line.Counter)
  line.render_statsd(m)
  |> should.equal("nginz.req:1|c|#s:ok")
}

pub fn helpers_error_event_test() {
  let m = helpers.error_event("fail", [line.Tag(name: "route", value: "/api")])
  m.value |> should.equal(1)
  m.metric_type |> should.equal(line.Counter)
  // Error event renders with error:true tag
  let rendered = line.render_statsd(m)
  // Tags are ordered as [error:true, route:/api]
  rendered
  |> should.equal("nginz.fail:1|c|#error:true,route:/api")
}

pub fn helpers_gauge_test() {
  let m = helpers.gauge("connections", 10, [])
  m.metric_type |> should.equal(line.Gauge)
  m.value |> should.equal(10)
}

pub fn helpers_timing_test() {
  let m = helpers.timing("latency", 42, [])
  m.metric_type |> should.equal(line.Timing)
  m.value |> should.equal(42)
}

pub fn helpers_latency_test() {
  let m = helpers.latency("latency", 99, [])
  m.metric_type |> should.equal(line.Timing)
  m.value |> should.equal(99)
}

pub fn helpers_distribution_test() {
  let m = helpers.distribution("dist", 100, [])
  m.metric_type |> should.equal(line.Distribution)
}

pub fn helpers_set_test() {
  let m = helpers.set("users", 42, [])
  m.metric_type |> should.equal(line.Set)
}

// --- Tag constructor tests ---

pub fn tag_service_test() {
  helpers.tag_service("authz")
  |> should.equal(line.Tag(name: "service", value: "authz"))
}

pub fn tag_status_test() {
  helpers.tag_status(200)
  |> should.equal(line.Tag(name: "status", value: "200"))
}

pub fn tag_route_test() {
  helpers.tag_route("/api/users")
  |> should.equal(line.Tag(name: "route", value: "/api/users"))
}

pub fn tag_method_test() {
  helpers.tag_method("POST")
  |> should.equal(line.Tag(name: "method", value: "POST"))
}

pub fn tag_result_test() {
  helpers.tag_result("success")
  |> should.equal(line.Tag(name: "result", value: "success"))
}

// --- MetricError text tests ---

pub fn error_text_empty_name_test() {
  line.error_text(line.EmptyName)
  |> should.equal("metric name must not be empty")
}

pub fn error_text_invalid_name_test() {
  line.error_text(line.InvalidNameChar("bad:name"))
  |> should.equal("metric name contains illegal character: bad:name")
}

pub fn error_text_negative_counter_test() {
  line.error_text(line.NegativeCounterValue)
  |> should.equal("counter value must be non-negative")
}

pub fn error_text_invalid_sample_rate_test() {
  line.error_text(line.InvalidSampleRate)
  |> should.equal("sample rate must be > 0.0 and <= 1.0, got invalid value")
}

pub fn describe_error_test() {
  line.describe_error(line.EmptyName)
  |> should.equal("metric validation error: metric name must not be empty")
}
