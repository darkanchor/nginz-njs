import authz/policy.{type Context, type Decision, Allow, Deny}
import gleam/dict
import gleam/string
import njs/http.{type HTTPRequest}

/// Set the `X-Authz-Status` response header to `allow` or `deny`.
/// The upstream proxy can forward this header to the backend service.
pub fn inject_status(r: HTTPRequest, decision: Decision) -> HTTPRequest {
  let status = case decision {
    Allow -> "allow"
    Deny(_) -> "deny"
  }
  http.set_headers_out(r, "X-Authz-Status", status)
}

/// Set `X-Authz-<Claim>` response headers for every entry in `ctx.claims`.
/// Claim names are title-cased, e.g. `role` → `X-Authz-Role`.
pub fn inject_claims(r: HTTPRequest, ctx: Context) -> HTTPRequest {
  dict.fold(ctx.claims, r, fn(r, key, value) {
    http.set_headers_out(r, "X-Authz-" <> title_case(key), value)
  })
}

fn title_case(s: String) -> String {
  case string.split(s, "") {
    [] -> ""
    [first, ..rest] -> string.uppercase(first) <> string.join(rest, "")
  }
}
