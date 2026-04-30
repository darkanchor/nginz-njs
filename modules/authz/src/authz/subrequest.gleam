import authz/policy.{type AsyncRule, type Context, type Decision, Allow, Deny}
import gleam/int
import gleam/javascript/promise.{type Promise}
import njs/http.{type HTTPRequest}
import njs/ngx

/// Build an AsyncRule that delegates the authorization decision to an nginx
/// internal location via a subrequest. A 2xx response maps to Allow; any other
/// status maps to Deny(403, ...). The original HTTPRequest `r` is captured in
/// the closure so the subrequest inherits its context.
///
/// Typical use:
///
///     let rules: List(AsyncRule) = [
///       to_async(method_in(["GET", "POST"])),
///       subrequest.auth_request_step(r, "/auth"),
///     ]
///     async_evaluate(ctx, rules)
pub fn auth_request_step(r: HTTPRequest, path: String) -> AsyncRule {
  fn(_ctx: Context) -> Promise(Decision) {
    use resp <- promise.await(http.subrequest(r, path, ngx.object()))
    let status = http.status(resp)
    case status >= 200 && status < 300 {
      True -> promise.resolve(Allow)
      False ->
        promise.resolve(Deny(
          403,
          "subrequest denied: " <> int.to_string(status),
        ))
    }
  }
}
