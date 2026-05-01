import gleam/string
import gleeunit
import gleeunit/should
import health_gateway/metrics
import health_gateway/model.{
  AllHealthy, AllUnhealthy, Allow, Block, Degraded, aggregate, backend_summary,
  gate_decision, healthy_backend, unhealthy_backend,
}
import health_gateway/response
import metrics/line

pub fn main() {
  gleeunit.main()
}

// --- model tests ---

pub fn healthy_backend_test() {
  let h = healthy_backend("api", 99)
  h.name |> should.equal("api")
  h.healthy |> should.equal(True)
  h.success_rate |> should.equal(99)
}

pub fn unhealthy_backend_test() {
  let h = unhealthy_backend("db", 3)
  h.name |> should.equal("db")
  h.healthy |> should.equal(False)
  h.consecutive_failures |> should.equal(3)
}

pub fn aggregate_all_healthy_test() {
  let backends = [healthy_backend("api", 99), healthy_backend("db", 100)]
  aggregate(backends) |> should.equal(AllHealthy)
}

pub fn aggregate_all_unhealthy_test() {
  let backends = [unhealthy_backend("api", 5), unhealthy_backend("db", 3)]
  aggregate(backends) |> should.equal(AllUnhealthy)
}

pub fn aggregate_degraded_test() {
  let backends = [healthy_backend("api", 99), unhealthy_backend("db", 3)]
  aggregate(backends)
  |> should.equal(Degraded(healthy_count: 1, total_count: 2))
}

pub fn aggregate_empty_test() {
  aggregate([]) |> should.equal(AllUnhealthy)
}

pub fn gate_decision_healthy_test() {
  gate_decision(AllHealthy) |> should.equal(Allow)
}

pub fn gate_decision_degraded_test() {
  gate_decision(Degraded(1, 2)) |> should.equal(Allow)
}

pub fn gate_decision_unhealthy_test() {
  gate_decision(AllUnhealthy)
  |> should.equal(Block("All backends are unhealthy"))
}

pub fn backend_summary_test() {
  backend_summary(healthy_backend("api", 95))
  |> should.equal("api=healthy(95%)")
}

pub fn backend_summary_unhealthy_test() {
  backend_summary(unhealthy_backend("db", 3))
  |> should.equal("db=unhealthy(0%)")
}

// --- response tests ---

pub fn aggregate_json_healthy_test() {
  let backends = [healthy_backend("api", 99)]
  let body = response.aggregate_json(AllHealthy, backends)
  string.contains(body, "\"status\":\"healthy\"") |> should.equal(True)
  string.contains(body, "\"name\":\"api\"") |> should.equal(True)
}

pub fn aggregate_json_degraded_test() {
  let backends = [healthy_backend("api", 99), unhealthy_backend("db", 3)]
  let body = response.aggregate_json(Degraded(1, 2), backends)
  string.contains(body, "\"status\":\"degraded\"") |> should.equal(True)
}

pub fn readiness_json_test() {
  let body = response.readiness_json(True, "ok")
  string.contains(body, "\"ready\":true") |> should.equal(True)
  string.contains(body, "\"reason\":\"ok\"") |> should.equal(True)
}

pub fn readiness_json_not_ready_test() {
  let body = response.readiness_json(False, "backends down")
  string.contains(body, "\"ready\":false") |> should.equal(True)
  string.contains(body, "\"reason\":\"backends down\"") |> should.equal(True)
}

// --- metrics tests ---

pub fn aggregate_counter_healthy_test() {
  let m = metrics.aggregate_counter(AllHealthy, "/health")
  line.render_statsd(m)
  |> should.equal(
    "nginz.health_gateway_aggregate_total:1|c|#status:healthy,route:/health",
  )
}

pub fn aggregate_counter_unhealthy_test() {
  let m = metrics.aggregate_counter(AllUnhealthy, "/health")
  line.render_statsd(m)
  |> should.equal(
    "nginz.health_gateway_aggregate_total:1|c|#status:unhealthy,route:/health",
  )
}

pub fn gate_counter_allow_test() {
  let m = metrics.gate_counter(True, "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.health_gateway_gate_total:1|c|#decision:allow,route:/api",
  )
}

pub fn gate_counter_block_test() {
  let m = metrics.gate_counter(False, "/api")
  line.render_statsd(m)
  |> should.equal(
    "nginz.health_gateway_gate_total:1|c|#decision:block,route:/api",
  )
}
