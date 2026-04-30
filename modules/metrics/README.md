# nginz_njs_metrics

Push-based metrics forwarding scaffold for nginx written in Gleam. The long-term goal is a reusable instrumentation surface that other modules emit into, rather than each module formatting StatsD/DogStatsD lines on its own.

## Roadmap position

`metrics` is a Tier-2 module in `ROADMAP.md`. It has no native blocker and belongs in the scripted layer because protocol serialization and log-phase event shaping are pure string/data tasks rather than performance-critical native primitives.

## Design goals

- keep metric definitions and tag formatting pure and reusable
- make protocol line rendering explicit and testable
- let `workflow`, `http_client`, `authz`, and `webhook` emit into this module rather than re-owning formatting
- keep transport/emission wiring out of the scaffold phase

## What is implemented

**`metrics/line.gleam`**
- `MetricType`, `Tag`, and `Metric`
- `demo_metric` and `render_statsd` scaffold helpers

**`nginz_njs_metrics.gleam`**
- `describe` — returns the metric name and type summary
- `emit_demo` — returns a deterministic StatsD-style rendered line

**Integration tests**
- `tests/basic/` — verifies scaffold handlers return stable responses with stock nginx only

## Core abstractions

- `Metric` — the reusable instrumentation value
- `MetricType` — counter/gauge/timing semantics
- `Tag` — explicit metadata for downstream sinks
- future emitters — transport-specific logic that should sit on top of the pure metric model

The architectural rule for this module is: metrics formatting belongs in a reusable Gleam library, and emission points in other modules should pass structured events into it rather than formatting protocol strings inline.

## Cross-module composition boundary

- `http_client` should later emit latency and failure events through `metrics`
- `workflow` should later emit step and pipeline events through `metrics`
- `authz` should later emit decision and denial events through `metrics`
- `webhook` should later emit delivery and verification events through `metrics`

## Scripted core vs optional native integration

### Scripted core

- metric/event modeling
- tag formatting and protocol serialization
- reusable instrumentation helpers

### Optional native integration

- none required for the baseline scaffold
- native transport or queueing could later complement this, but the event model should stay scripted and reusable

## Phased implementation plan

### Phase 1 — stabilize the event model

Goal: define reusable metrics values before real emission.

- [ ] expand `Metric` with sample rate, namespace, and richer tags
- [ ] keep rendering deterministic and testable
- [ ] add validation for invalid tag/value combinations

### Phase 2 — add reusable emit helpers

Goal: make other modules depend on `metrics` instead of formatting strings themselves.

- [ ] add helper constructors for common latency, counter, and error events
- [ ] document instrumentation insertion points for `http_client`, `workflow`, and `authz`
- [ ] keep transport concerns out of the core model

### Phase 3 — add real emission adapters

Goal: connect the pure metric model to log-phase or push-based transport.

- [ ] add StatsD/DogStatsD emission adapters
- [ ] add batching or sink configuration only after the event contract is stable
- [ ] keep emission failure handling separate from event modeling

## TDD plan

- [ ] unit-test line rendering and tag ordering first
- [ ] add pure tests for metric helpers before any transport work
- [ ] keep real emission behind later targeted integration tests

## Atomic commit strategy

- [ ] `metrics: add pure metric model scaffold`
- [ ] `metrics: add reusable instrumentation helpers`
- [ ] `metrics: add first emission adapter`
- [ ] `docs: document cross-module instrumentation points`

## Verification checklist

- [ ] `bun scripts/test.js metrics` — unit tests pass
- [ ] `bun test modules/metrics/tests/basic/do.test.js` — basic integration passes
