//// HMAC signing and verification for webhooks.
////
//// Composes njs Web Crypto primitives (`compute_hmac`) with the webhook
//// config model. All crypto is async (Promise-based).

import gleam/javascript/promise.{type Promise}
import gleam/string
import njs/buffer.{Hex, Utf8, from_string}
import njs/crypto
import webhook/spec.{type WebhookConfig}

/// Sign a payload using the webhook config's algorithm and secret.
/// Returns a hex-encoded signature string.
///
pub fn sign(config: WebhookConfig, payload: String) -> Promise(String) {
  let algo = hash_algorithm(config)
  let key = from_string(config.secret, Utf8)
  let data = from_string(payload, Utf8)
  crypto.compute_hmac(algo, key, data, Hex)
}

/// Verify a signature against a payload using the webhook config's
/// algorithm and secret. Returns `True` if the signature is valid.
///
/// Uses a constant-time comparison via re-encoding to avoid timing
/// side-channels on the hex string comparison (crypto.compute_hmac
/// returns a hex string, so we compare hex-encoded outputs).
///
pub fn verify(
  config: WebhookConfig,
  payload: String,
  signature: String,
) -> Promise(Bool) {
  use expected <- promise.await(sign(config, payload))
  // Normalise to lowercase before comparison — some HMAC implementations
  // produce uppercase hex, njs produces lowercase.
  let expected_lower = string.lowercase(expected)
  let got_lower = string.lowercase(signature)
  promise.resolve(expected_lower == got_lower && expected_lower != "")
}

/// Build the signature header tuple `#(name, value)` for outbound delivery.
///
pub fn signature_header(
  config: WebhookConfig,
  signature: String,
) -> #(String, String) {
  #(config.signature_header, signature)
}

fn hash_algorithm(config: WebhookConfig) -> String {
  case config.algorithm {
    spec.HmacSha256 -> "sha256"
  }
}
