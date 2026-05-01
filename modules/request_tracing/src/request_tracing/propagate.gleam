//// Request ID propagation. Injects trace headers into upstream requests
//// and subrequests so the request ID flows through the entire call chain.

import request_tracing/model.{type TraceContext}

/// Headers to inject into upstream requests for trace propagation.
pub fn propagation_headers(ctx: TraceContext) -> List(#(String, String)) {
  [
    #(model.request_id_header, ctx.request_id),
    #(model.trace_id_header, ctx.request_id),
  ]
}

/// Build a header injection string for nginx proxy_set_header directives.
/// Returns the headers as a flat list of name-value pairs.
pub fn inject_upstream(ctx: TraceContext) -> List(#(String, String)) {
  propagation_headers(ctx)
}
