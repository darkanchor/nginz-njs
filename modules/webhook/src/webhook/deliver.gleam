//// Outbound webhook delivery — composes `http_client` for transport and
//// `webhook/sign` for payload signing.

import gleam/javascript/promise.{type Promise}
import http_client/client.{Post}
import http_client/fetch.{
  type ClientError, type Response, FetchFailed, InvalidRequest, InvalidUrl,
  Timeout, execute,
}
import webhook/sign
import webhook/spec.{type WebhookConfig}

/// Errors specific to webhook delivery.
///
pub type DeliveryError {
  /// The webhook config failed validation.
  ConfigInvalid(reason: String)
  /// HMAC signing failed (should not happen with valid input).
  SignFailed(reason: String)
  /// The upstream request failed — wraps the underlying http_client error.
  UpstreamFailed(error: ClientError)
}

/// Sign a payload and deliver it to the configured webhook endpoint.
///
/// Composes `webhook/sign` + `http_client` execution. Returns the upstream
/// `Response` on success, or a typed `DeliveryError`.
///
pub fn deliver(
  config: WebhookConfig,
  payload: String,
) -> Promise(Result(Response, DeliveryError)) {
  case spec.validate(config) {
    Error(err) -> promise.resolve(Error(ConfigInvalid(spec.error_text(err))))
    Ok(_) -> {
      use signature <- promise.await(sign.sign(config, payload))
      let sig_header = sign.signature_header(config, signature)
      let req =
        client.new(config.url)
        |> client.with_method(Post)
        |> client.with_body(payload)
        |> client.with_timeout(config.timeout_ms)
        |> client.with_headers(config.headers)
        |> client.with_header(sig_header.0, sig_header.1)
      use result <- promise.await(execute(req))
      promise.resolve(case result {
        Ok(resp) -> Ok(resp)
        Error(err) -> Error(UpstreamFailed(err))
      })
    }
  }
}

/// Deliver a webhook with retry policy. Retries up to `config.retry_max_attempts`
/// additional times on retryable errors (timeout, fetch failure, 5xx responses).
///
pub fn deliver_with_retry(
  config: WebhookConfig,
  payload: String,
) -> Promise(Result(Response, DeliveryError)) {
  do_deliver_with_retry(config, payload, config.retry_max_attempts)
}

fn do_deliver_with_retry(
  config: WebhookConfig,
  payload: String,
  remaining: Int,
) -> Promise(Result(Response, DeliveryError)) {
  use result <- promise.await(deliver(config, payload))
  case result {
    Ok(resp) ->
      case is_retryable_response(resp) && remaining > 0 {
        True -> do_deliver_with_retry(config, payload, remaining - 1)
        False -> promise.resolve(Ok(resp))
      }
    Error(err) ->
      case is_retryable_error(err) && remaining > 0 {
        True -> do_deliver_with_retry(config, payload, remaining - 1)
        False -> promise.resolve(Error(err))
      }
  }
}

fn is_retryable_response(resp: Response) -> Bool {
  resp.status >= 500 && resp.status < 600
}

fn is_retryable_error(err: DeliveryError) -> Bool {
  case err {
    UpstreamFailed(Timeout(_)) | UpstreamFailed(FetchFailed(_)) -> True
    UpstreamFailed(InvalidUrl(_)) | UpstreamFailed(InvalidRequest(_)) -> False
    ConfigInvalid(_) | SignFailed(_) -> False
  }
}
