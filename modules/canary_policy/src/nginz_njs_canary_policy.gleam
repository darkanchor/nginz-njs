//// njs entry point for canary_policy. Reads the native canary module's
//// $ngz_canary variable and applies scripted policy: header injection,
//// response tagging, and metrics emission.

import canary_policy/model.{type CanaryContext, Canary, Stable, Unknown}
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

/// Canary-routed handler. Reads $ngz_canary, injects X-Canary header,
/// and returns 204 with the routing decision logged.
fn canary_routed(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  let _ = inject_canary_header(r, ctx)
  let _ = http.log(r, "canary_policy: " <> model.summary(ctx))
  http.return_code(r, 204)
}

/// Canary-tagged handler. Adds X-Canary response header so downstream
/// consumers know which deployment served the request.
fn canary_tagged(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  let tag = case ctx.decision {
    Canary -> "true"
    Stable -> "false"
    Unknown -> "unknown"
  }
  let _ = http.set_headers_out(r, "X-Canary", tag)
  let _ = http.log(r, "canary_policy: tagged — " <> model.summary(ctx))
  http.return_code(r, 204)
}

/// Canary handler that emits metrics for the routing decision.
fn canary_with_metrics(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  let _ = inject_canary_header(r, ctx)
  let _ = http.log(r, "canary_policy: " <> model.summary(ctx))
  // Metrics emission would happen here in a real deployment:
  // let m = canary_metrics.decision_counter(ctx, http.uri(r))
  // let _ = line.render_statsd(m)
  http.return_code(r, 204)
}

// --- Internal helpers ---

fn read_context(r: HTTPRequest) -> CanaryContext {
  let vars = http.get_variables(r)
  let canary_value = case ngx.get(vars, "ngz_canary") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  model.context(canary_value)
}

fn inject_canary_header(r: HTTPRequest, ctx: CanaryContext) -> Nil {
  let header_value = case ctx.decision {
    Canary -> "true"
    Stable -> "false"
    Unknown -> "unknown"
  }
  let _ = http.set_headers_out(r, "X-Canary", header_value)
  Nil
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("canary_routed", canary_routed)
  |> ngx.merge("canary_tagged", canary_tagged)
  |> ngx.merge("canary_with_metrics", canary_with_metrics)
}
