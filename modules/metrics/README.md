# nginz_njs_metrics

Reusable metrics modeling and StatsD/DogStatsD line rendering for nginx written in Gleam. Provides a shared instrumentation surface that other modules emit into, rather than each module formatting protocol lines on its own.

## Use Case

**The problem**: every module wants to report what it is doing, but if each one invents its own metric names, tags, and output format, the result is messy dashboards and operational confusion.

**How it solves it**: this module gives the rest of the repo one shared way to describe and render metrics. That means the interesting part stays the signal itself, not the repeated string-formatting work or endless small inconsistencies between modules. That gives you one set of pieces you can reuse across modules, so the whole system can grow without turning into a pile of one-off metric styles.

**When you would use this**: use it when you want modules to speak the same operational language. It matters most when several pieces of the system need to be observed together and you do not want each one to feel like it came from a different team.

## Roadmap position

`metrics` is a Tier-2 module in `ROADMAP.md`. It has no native blocker and belongs in the scripted layer because protocol serialization and log-phase event shaping are pure string/data tasks rather than performance-critical native primitives.

## Design goals

- keep metric definitions and tag formatting pure and reusable
- make protocol line rendering explicit and testable
- let `http_client`, `authz`, `feature_flags`, `session`, `mlcache`, `response_transform`, `workflow`, and `webhook` emit into this module rather than re-owning formatting
- keep transport and sink wiring out of the core model

## What is implemented

**`metrics/line.gleam`** — core model + rendering
- `MetricType` — `Counter`, `Gauge`, `Timing`, `Set`, `Distribution`
- `Tag` — explicit metadata for downstream sinks (`name:value` pairs)
- `Metric` — the reusable instrumentation value with `name`, `value`, `metric_type`, `tags`, `sample_rate`, `namespace`
- `MetricError` — typed validation errors (`EmptyName`, `InvalidNameChar`, `EmptyTagName`, `InvalidTagNameChar`, `InvalidTagValueChar`, `NegativeCounterValue`, `InvalidSampleRate`)
- `Format` — `StatsD`, `DogStatsD`
- `validate(metric)` — validates name, tags, counter non-negativity, sample rate in (0.0, 1.0]
- `render_statsd(metric)` — StatsD line format: `<ns>.<name>:<value>|<type>[|@<rate>]|#<tags>`
- `render_dogstatsd(metric)` — DogStatsD format (identical for standard metric types)
- `render(metric, format)` — dispatch by Format
- `describe(metric)` — human-readable summary
- `error_text(error)` / `describe_error(error)` — error formatting
- `demo_metric()` — example metric for scaffold testing

**`metrics/helpers.gleam`** — reusable constructors for cross-module use
- `counter(name, value, tags)` — counter metric
- `gauge(name, value, tags)` — gauge metric
- `timing(name, value_ms, tags)` — timing metric (ms)
- `distribution(name, value, tags)` — DogStatsD distribution
- `set(name, value, tags)` — set metric
- `increment(name, tags)` — counter +1 shorthand
- `latency(name, ms, tags)` — timing alias
- `error_event(name, tags)` — error counter +1, auto-tagged with `error:true`
- Tag constructors: `tag_service`, `tag_status`, `tag_route`, `tag_method`, `tag_result`

**`nginz_njs_metrics.gleam`** — njs entry point
- `describe` — returns stable summary of the demo metric
- `emit_demo` — returns StatsD-rendered demo metric line
- `emit_statsd` — renders a metric from query params as StatsD
- `emit_dogstatsd` — renders a metric from query params as DogStatsD
- `validate_metric` — validates a metric from query params; returns "ok" or error text
- `describe_metric` — describes a metric from query params
- `emit_helper` — renders a metric using a named helper pattern (increment, error, timing, etc.)

**Integration tests**
- `tests/basic/` — 12 scenarios: scaffold handlers, query-param rendering (both formats), validation (ok + 3 error cases), describe, helper patterns (increment, error, timing)

## Core abstractions

- `Metric` — the reusable instrumentation value
- `MetricType` — counter/gauge/timing/set/distribution semantics
- `Tag` — explicit metadata for downstream sinks
- `MetricError` — typed validation failures
- Emitters (`render_statsd`, `render_dogstatsd`) — transport-specific logic sitting on top of the pure metric model

The architectural rule for this module is: metrics formatting belongs in a reusable Gleam library, and emission points in other modules should pass structured events into it rather than formatting protocol strings inline.

## Cross-module composition boundary

- `http_client` now exposes reusable request outcome and latency metrics adapters
- `authz` now exposes reusable decision and OPA call metrics adapters
- `feature_flags`, `session`, `mlcache`, and `response_transform` now expose reusable domain-specific metrics adapters
- `workflow` and `webhook` remain future adopters

### Usage pattern

Other modules should import `metrics/helpers` and construct `Metric` values:

```gleam
import metrics/helpers

// After a successful subrequest:
let success_metric =
  helpers.increment("http_requests_total", [
    helpers.tag_route("/api/users"),
    helpers.tag_status(200),
  ])

// On upstream failure:
let error_metric =
  helpers.error_event("upstream_failure", [
    helpers.tag_route("/api/users"),
    helpers.tag_status(502),
  ])

// Latency tracking:
let latency_metric =
  helpers.latency("upstream_duration_ms", 42, [
    helpers.tag_route("/api/users"),
  ])
```

The emission transport (StatsD UDP, DogStatsD, log-phase njs, or another sink) is a separate concern that consumes `Metric` values from the pure model layer.

## Scripted core vs optional native integration

### Scripted core

- metric/event modeling
- tag formatting and protocol serialization (StatsD, DogStatsD)
- reusable instrumentation helpers

### Optional native integration

- none required for the baseline
- native transport or queueing could later complement this, but the event model should stay scripted and reusable

## Phased implementation plan

### Phase 1 — stabilize the event model ✅

Goal: define reusable metrics values before real emission.

- [x] expand `Metric` with sample rate, namespace, and validation
- [x] keep rendering deterministic and testable
- [x] add `validate()` with typed `MetricError` for invalid tag/value combinations

### Phase 2 — add reusable emit helpers ✅

Goal: make other modules depend on `metrics` instead of formatting strings themselves.

- [x] add helper constructors: `counter`, `gauge`, `timing`, `increment`, `latency`, `error_event`, `distribution`, `set`
- [x] add tag constructors: `tag_service`, `tag_status`, `tag_route`, `tag_method`, `tag_result`
- [x] document instrumentation insertion points for `http_client`, `workflow`, and `authz`
- [x] keep transport concerns out of the core model

### Phase 3 — add protocol rendering adapters ✅

Goal: connect the pure metric model to concrete StatsD/DogStatsD line rendering without adding sink transport yet.

- [x] add StatsD and DogStatsD rendering adapters
- [ ] add batching or sink configuration only after the event contract is stable
- [x] keep emission failure handling separate from event modeling (validation is pre-emission)

### Phase 4 — milestone 3 emission and operator-facing transport

Goal: keep the metric model stable while making it easier for other modules and runtime tooling to move those values toward real sinks.

- [ ] add batching or sink configuration once the event contract and module consumers are stable enough to support it cleanly
- [ ] add composition examples for `workflow`, `webhook`, `request_tracing`, and `control_api`
- [ ] keep sink delivery and transport ownership separate from the pure metric/event model

## TDD plan

- [x] unit-test line rendering, tag ordering, sample rate, namespace (10 rendering tests)
- [x] unit-test describe output (2 describe tests)
- [x] unit-test validation: empty name, illegal chars, negative counter, sample rate range, empty/invalid tags (12 validation tests)
- [x] unit-test helper constructors: counter, gauge, timing, increment, error_event, distribution, set (8 helper tests)
- [x] unit-test tag constructors: service, status, route, method, result (5 tag tests)
- [x] unit-test error text formatting (5 error text tests)
- [x] add integration coverage for query-param rendering, validation, and helper patterns (12 integration tests)

## Atomic commit strategy

- [x] `metrics: add pure metric model with validation`
- [x] `metrics: add reusable instrumentation helpers`
- [x] `metrics: add StatsD and DogStatsD emission adapters`
- [x] `docs: document cross-module instrumentation points`

## Verification checklist

- [x] `bun scripts/test.js metrics` — 43 unit tests pass
- [x] `bun test modules/metrics/tests/basic/do.test.js` — 12 integration tests pass
- [x] `bun run build:module metrics` — builds successfully
- [x] Manual: `gleam test` in module directory — 43 unit tests pass
