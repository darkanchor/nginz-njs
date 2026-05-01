//// Inbound webhook verification — extracts signatures from incoming requests
//// and verifies them against the configured secret.

import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/string
import webhook/sign
import webhook/spec.{type WebhookConfig}

/// Errors specific to inbound webhook verification.
///
pub type VerifyError {
  MissingSignature(header: String)
  InvalidSignature(header: String, got: String)
  InvalidPayload
}

/// Extract the signature from a set of request headers.
///
/// Headers are represented as `List(#(String, String))` (the njs/http raw
/// headers format). The lookup is case-insensitive.
///
pub fn extract_signature(
  headers: List(#(String, String)),
  config: WebhookConfig,
) -> Result(String, VerifyError) {
  let target = string.lowercase(config.signature_header)
  case
    list.find_map(headers, fn(hdr) {
      case string.lowercase(hdr.0) == target {
        True -> Ok(hdr.1)
        False -> Error(Nil)
      }
    })
  {
    Ok(sig) -> Ok(sig)
    Error(_) -> Error(MissingSignature(config.signature_header))
  }
}

/// Fully verify an inbound webhook request.
///
/// Takes raw headers and the raw request body. Extracts the signature header,
/// verifies it against the payload using the configured secret and algorithm.
///
pub fn verify_request(
  headers: List(#(String, String)),
  body: String,
  config: WebhookConfig,
) -> Promise(Result(Nil, VerifyError)) {
  case extract_signature(headers, config) {
    Error(err) -> promise.resolve(Error(err))
    Ok(signature) -> {
      use valid <- promise.await(sign.verify(config, body, signature))
      promise.resolve(case valid {
        True -> Ok(Nil)
        False -> Error(InvalidSignature(config.signature_header, signature))
      })
    }
  }
}
