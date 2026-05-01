//// Transform http_client fetch results into `metrics` instrumentation values.
////
//// These are adapter functions that map domain-specific outcomes (success,
//// timeout, fetch failure) into the generic `Metric` type. Callers render
//// and emit through the `metrics` module surface; this module only produces
//// the structured metric values.

import http_client/fetch.{
  type ClientError, FetchFailed, InvalidRequest, InvalidUrl, Timeout,
}
import metrics/helpers
import metrics/line.{type Metric, type Tag}

/// Produce an outcome counter for a completed fetch attempt.
///
/// `route` is a stable pattern like `"/api/users"` or `"opa"` — not the
/// full dynamic URL. `latency_ms` is the observed round-trip time; pass 0
/// when not measured (e.g. pre-flight validation failures).
///
pub fn request_outcome(
  result: Result(fetch.Response, ClientError),
  route: String,
  latency_ms: Int,
) -> Metric {
  case result {
    Ok(resp) -> request_success(resp, route, latency_ms)
    Error(err) -> request_failure(err, route)
  }
}

/// Produce a success counter + latency timing pair (returns the counter;
/// callers should also emit a separate timing metric via `request_latency`).
///
pub fn request_success(
  resp: fetch.Response,
  route: String,
  _latency_ms: Int,
) -> Metric {
  helpers.increment("http_client_request_total", [
    helpers.tag_route(route),
    helpers.tag_status(resp.status),
    helpers.tag_result("success"),
  ])
}

/// Produce a latency timing metric for a successful request.
///
pub fn request_latency(route: String, latency_ms: Int) -> Metric {
  helpers.latency("http_client_latency_ms", latency_ms, [
    helpers.tag_route(route),
  ])
}

/// Produce an error counter for a failed fetch attempt.
///
pub fn request_failure(err: ClientError, route: String) -> Metric {
  let reason = error_tag(err)
  helpers.error_event("http_client_error_total", [
    helpers.tag_route(route),
    reason,
  ])
}

/// Produce a single summary metric combining outcome + latency into one
/// counter. Useful when the caller wants a single emission point rather
/// than separate counter and timing.
///
pub fn request_summary(
  result: Result(fetch.Response, ClientError),
  route: String,
  latency_ms: Int,
) -> #(Metric, Metric) {
  let outcome = request_outcome(result, route, latency_ms)
  let timing = case result {
    Ok(_) -> request_latency(route, latency_ms)
    Error(_) ->
      helpers.latency("http_client_latency_ms", latency_ms, [
        helpers.tag_route(route),
        helpers.tag_result("error"),
      ])
  }
  #(outcome, timing)
}

fn error_tag(err: ClientError) -> Tag {
  case err {
    Timeout(_) -> helpers.tag_result("timeout")
    FetchFailed(_) -> helpers.tag_result("fetch_failed")
    InvalidUrl(_) -> helpers.tag_result("invalid_url")
    InvalidRequest(_) -> helpers.tag_result("invalid_request")
  }
}
