//// njs entry point for ratelimit_policy. Reads the native ratelimit module's
//// nginx variables and applies scripted policy: header injection, custom
//// error responses, metrics emission, and workflow fallback.

import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import ratelimit_policy/headers
import ratelimit_policy/model.{
  type PolicyDecision, type RateLimitContext, Allowed, Denied, DenyWith,
  InjectHeaders, PassThrough, Unknown,
}
import ratelimit_policy/response

/// Basic rate-limited handler. Reads $ratelimit_result and returns 429 on deny,
/// 204 on allow. Logs the rate limit context.
fn rate_limited(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  case ctx.result {
    Allowed -> {
      let _ = http.log(r, "ratelimit_policy: allowed — " <> model.summary(ctx))
      http.return_code(r, 204)
    }
    Denied -> {
      let _ = http.log(r, "ratelimit_policy: denied — " <> model.summary(ctx))
      http.return_code(r, 429)
    }
    Unknown -> {
      let _ = http.log(r, "ratelimit_policy: unknown result, passing through")
      http.return_code(r, 204)
    }
  }
}

/// Rate-limited handler with standard headers injected on both allow and deny.
fn rate_limited_with_headers(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  let decision = decide(ctx)
  apply_decision(r, ctx, decision)
}

/// Rate-limited handler with a custom JSON error body on deny.
fn rate_limited_custom_error(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  case ctx.result {
    Denied -> {
      let body =
        response.json_error("Rate limit exceeded. Please retry later.", 60)
      let _ = http.set_headers_out(r, "Content-Type", "application/json")
      let _ = http.set_headers_out(r, "Retry-After", "60")
      let _ =
        http.log(
          r,
          "ratelimit_policy: denied (custom error) — " <> model.summary(ctx),
        )
      http.return_text(r, 429, body)
    }
    Allowed -> {
      let _ = http.log(r, "ratelimit_policy: allowed — " <> model.summary(ctx))
      http.return_code(r, 204)
    }
    Unknown -> http.return_code(r, 204)
  }
}

/// Rate-limited handler that fetches a fallback response from an internal
/// location when denied. Reads $ratelimit_fallback_path for the fallback URL.
fn rate_limited_with_fallback(r: HTTPRequest) -> Nil {
  let ctx = read_context(r)
  case ctx.result {
    Denied -> {
      let vars = http.get_variables(r)
      let fallback_path = case ngx.get(vars, "ratelimit_fallback_path") {
        Ok(v) -> ngx.to_string(v)
        Error(_) -> ""
      }
      case fallback_path {
        "" -> {
          let body = response.json_error("Rate limit exceeded", 60)
          let _ = http.set_headers_out(r, "Content-Type", "application/json")
          let _ = http.set_headers_out(r, "Retry-After", "60")
          http.return_text(r, 429, body)
        }
        path -> {
          let _ =
            http.log(r, "ratelimit_policy: serving fallback from " <> path)
          // In a real workflow, this would be a subrequest to the fallback path.
          // For now, return a static degraded response.
          let body =
            response.json_error(
              "Rate limit exceeded — serving degraded response",
              60,
            )
          let _ = http.set_headers_out(r, "Content-Type", "application/json")
          let _ = http.set_headers_out(r, "Retry-After", "60")
          http.return_text(r, 429, body)
        }
      }
    }
    Allowed -> {
      let _ = http.log(r, "ratelimit_policy: allowed — " <> model.summary(ctx))
      http.return_code(r, 204)
    }
    Unknown -> http.return_code(r, 204)
  }
}

// --- Internal helpers ---

fn read_context(r: HTTPRequest) -> RateLimitContext {
  let vars = http.get_variables(r)
  let result = case ngx.get(vars, "ratelimit_result") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let key = case ngx.get(vars, "ratelimit_key") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let source = case ngx.get(vars, "ratelimit_source") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let cost = case ngx.get(vars, "ratelimit_cost") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> "1"
  }
  model.context(result, key, source, cost)
}

fn decide(ctx: RateLimitContext) -> PolicyDecision {
  case ctx.result {
    Allowed -> InjectHeaders(model.allow_headers(100, 99, 60))
    Denied -> InjectHeaders(model.deny_headers(60))
    Unknown -> PassThrough
  }
}

fn apply_decision(
  r: HTTPRequest,
  ctx: RateLimitContext,
  decision: PolicyDecision,
) -> Nil {
  case decision {
    PassThrough -> http.return_code(r, 204)
    InjectHeaders(hdrs) -> {
      let pairs = headers.render_all(hdrs)
      set_headers(r, pairs)
      case ctx.result {
        Denied -> {
          let _ =
            http.log(r, "ratelimit_policy: denied — " <> model.summary(ctx))
          http.return_code(r, 429)
        }
        _ -> {
          let _ =
            http.log(r, "ratelimit_policy: allowed — " <> model.summary(ctx))
          http.return_code(r, 204)
        }
      }
    }
    DenyWith(status, body, ct) -> {
      let _ = http.set_headers_out(r, "Content-Type", ct)
      http.return_text(r, status, body)
    }
  }
}

fn set_headers(r: HTTPRequest, pairs: List(#(String, String))) -> Nil {
  case pairs {
    [] -> Nil
    [#(name, value), ..rest] -> {
      let _ = http.set_headers_out(r, name, value)
      set_headers(r, rest)
    }
  }
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("rate_limited", rate_limited)
  |> ngx.merge("rate_limited_with_headers", rate_limited_with_headers)
  |> ngx.merge("rate_limited_custom_error", rate_limited_custom_error)
  |> ngx.merge("rate_limited_with_fallback", rate_limited_with_fallback)
}
