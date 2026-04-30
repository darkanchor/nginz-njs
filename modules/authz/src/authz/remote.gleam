import authz/policy.{type Context, type Decision, Allow, Deny}
import gleam/dynamic/decode
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/json
import http_client/client
import http_client/fetch

/// POST the authorization context to an OPA-compatible endpoint and return
/// Allow or Deny based on `{"result":{"allow":true}}` in the response body.
///
/// The endpoint is expected to follow the OPA REST API shape. On network
/// error or unparseable response the function returns Deny (fail-closed).
pub fn opa_allow(
  ctx: Context,
  endpoint: String,
  timeout_ms: Int,
) -> Promise(Decision) {
  let req =
    client.new(endpoint)
    |> client.with_method(client.Post)
    |> client.with_header("Content-Type", "application/json")
    |> client.with_body(opa_input(ctx))
    |> client.with_timeout(timeout_ms)
  use result <- promise.await(fetch.execute(req))
  promise.resolve(case result {
    Error(e) -> Deny("remote authz unavailable: " <> error_text(e))
    Ok(resp) ->
      case parse_allow(resp.body) {
        Ok(True) -> Allow
        Ok(False) -> Deny("remote authz: denied")
        Error(reason) -> Deny(reason)
      }
  })
}

fn opa_input(ctx: Context) -> String {
  json.object([
    #(
      "input",
      json.object([
        #("method", json.string(ctx.method)),
        #("path", json.string(ctx.path)),
        #("remote_addr", json.string(ctx.remote_addr)),
      ]),
    ),
  ])
  |> json.to_string
}

fn parse_allow(body: String) -> Result(Bool, String) {
  case json.parse(body, decode.at(["result", "allow"], decode.bool)) {
    Ok(allow) -> Ok(allow)
    Error(_) -> Error("remote authz: unexpected response")
  }
}

fn error_text(e: fetch.ClientError) -> String {
  case e {
    fetch.FetchFailed(r) -> r
    fetch.Timeout(ms) -> "timeout after " <> int.to_string(ms) <> "ms"
    fetch.InvalidUrl(u) -> "invalid url: " <> u
    fetch.InvalidRequest(r) -> r
  }
}
