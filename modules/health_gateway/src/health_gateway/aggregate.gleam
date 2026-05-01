//// Health aggregation. Fetches health from multiple backends via http_client
//// subrequests and computes overall status. Placeholder stub — full
//// subrequest-based aggregation is deferred to Phase 2.

import health_gateway/model.{type AggregateStatus, type BackendHealth, aggregate}

/// Fetch health from multiple backends and compute aggregate status.
/// Currently returns empty — full implementation will use http_client
/// subrequests to healthcheck endpoints.
pub fn fetch_aggregate(_backends: List(BackendHealth)) -> AggregateStatus {
  aggregate([])
}
