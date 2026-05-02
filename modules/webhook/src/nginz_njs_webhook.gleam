import gleam/int
import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/json
import gleam/result
import http_client/fetch
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import webhook/deliver
import webhook/sign
import webhook/spec
import webhook/verify

// --- Scaffold handlers (kept from Phase 0) ---

fn describe_outbound(r: HTTPRequest) -> Nil {
  spec.demo_outbound()
  |> spec.summary
  |> http.return_text(r, 200, _)
}

fn describe_inbound(r: HTTPRequest) -> Nil {
  spec.demo_inbound()
  |> spec.summary
  |> http.return_text(r, 200, _)
}

// --- Signing demo ---

/// Sign a JSON payload with the demo outbound config and return the
/// hex-encoded HMAC-SHA256 signature.
///
fn sign_demo(r: HTTPRequest) -> Promise(Nil) {
  let config = spec.demo_outbound()
  let payload = demo_payload()
  use sig <- promise.await(sign.sign(config, payload))
  http.return_text(r, 200, sig)
  promise.resolve(Nil)
}

// --- Verification demo ---

/// Verify an inbound request's signature. Reads the signature header
/// (`X-Signature`) and compares it against the HMAC of the request body.
///
fn verify_demo(r: HTTPRequest) -> Promise(Nil) {
  let config = spec.demo_inbound()
  let headers = http.raw_headers_in(r) |> array.to_list
  let body = http.request_text(r)
  use result <- promise.await(verify.verify_request(headers, body, config))
  case result {
    Ok(_) -> {
      http.return_text(r, 200, "ok")
      promise.resolve(Nil)
    }
    Error(err) -> {
      http.return_text(r, 401, verify_error_text(err))
      promise.resolve(Nil)
    }
  }
}

// --- Delivery demo ---

/// Sign and deliver a JSON payload to the demo outbound webhook endpoint.
/// Requires an upstream fixture at `/__fixture/upstream` or a real target.
///
fn deliver_demo(r: HTTPRequest) -> Promise(Nil) {
  let config =
    spec.WebhookConfig(
      ..spec.demo_outbound(),
      url: case http.get_variable(r, "webhook_demo_url") {
        Ok(v) -> v
        Error(_) -> spec.demo_outbound().url
      },
      timeout_ms: case http.get_variable(r, "webhook_demo_timeout_ms") {
        Ok(v) -> result.unwrap(int.parse(v), spec.demo_outbound().timeout_ms)
        Error(_) -> spec.demo_outbound().timeout_ms
      },
      retry_max_attempts: case
        http.get_variable(r, "webhook_demo_retry_max_attempts")
      {
        Ok(v) ->
          result.unwrap(int.parse(v), spec.demo_outbound().retry_max_attempts)
        Error(_) -> spec.demo_outbound().retry_max_attempts
      },
    )
  let payload = demo_payload()
  use result <- promise.await(deliver.deliver(config, payload))
  case result {
    Ok(resp) -> {
      http.return_text(r, resp.status, resp.body)
      promise.resolve(Nil)
    }
    Error(err) -> {
      http.return_text(r, 502, deliver_error_text(err))
      promise.resolve(Nil)
    }
  }
}

// --- Fixture endpoint for integration tests ---

/// Returns a static signed webhook fixture that `verify_demo` can consume.
/// Sets `X-Signature` to the HMAC-SHA256 of the demo payload and returns the
/// payload as the body.
///
fn signed_fixture(r: HTTPRequest) -> Promise(Nil) {
  let config = spec.demo_outbound()
  let payload = demo_payload()
  use sig <- promise.await(sign.sign(config, payload))
  let _ = http.set_headers_out(r, config.signature_header, sig)
  http.return_text(r, 200, payload)
  promise.resolve(Nil)
}

// --- Helpers ---

fn demo_payload() -> String {
  json.object([
    #("event", json.string("test.event")),
    #("timestamp", json.string("2025-01-01T00:00:00Z")),
    #("data", json.object([#("id", json.int(42))])),
  ])
  |> json.to_string
}

fn verify_error_text(err: verify.VerifyError) -> String {
  case err {
    verify.MissingSignature(h) -> "missing signature header: " <> h
    verify.InvalidSignature(h, s) -> "invalid signature: " <> h <> "=" <> s
    verify.InvalidPayload -> "invalid payload"
  }
}

fn deliver_error_text(err: deliver.DeliveryError) -> String {
  case err {
    deliver.ConfigInvalid(r) -> "config invalid: " <> r
    deliver.SignFailed(r) -> "sign failed: " <> r
    deliver.UpstreamFailed(e) -> "upstream failed: " <> fetch_error_text(e)
  }
}

fn fetch_error_text(err: fetch.ClientError) -> String {
  case err {
    fetch.FetchFailed(r) -> r
    fetch.Timeout(ms) -> "timeout after " <> int.to_string(ms) <> "ms"
    fetch.InvalidUrl(u) -> "invalid url: " <> u
    fetch.InvalidRequest(r) -> r
  }
}

// --- NJS exports ---

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe_outbound", describe_outbound)
  |> ngx.merge("describe_inbound", describe_inbound)
  |> ngx.merge("sign_demo", sign_demo)
  |> ngx.merge("verify_demo", verify_demo)
  |> ngx.merge("deliver_demo", deliver_demo)
  |> ngx.merge("signed_fixture", signed_fixture)
}
