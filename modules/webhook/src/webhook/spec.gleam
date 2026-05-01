//// Webhook config model — pure, reusable descriptors for outbound and
//// inbound webhook behaviour. All policy decisions (signing, delivery,
//// verification) compose on top of these config values.

import gleam/int
import gleam/list

// --- Types ---

pub type Algorithm {
  HmacSha256
}

pub type DeliveryMode {
  Outbound
  Inbound
}

/// A complete webhook configuration.
///
/// For outbound webhooks, `url` is the delivery target and `secret` is the
/// shared HMAC key used to sign the payload. For inbound webhooks, `url`
/// identifies the expected source and `secret` is used for verification.
///
pub type WebhookConfig {
  WebhookConfig(
    name: String,
    algorithm: Algorithm,
    delivery_mode: DeliveryMode,
    signature_header: String,
    url: String,
    secret: String,
    headers: List(#(String, String)),
    timeout_ms: Int,
    retry_max_attempts: Int,
  )
}

pub type ConfigError {
  EmptyName
  EmptyUrl
  EmptySecret
  InvalidTimeout
  InvalidRetryAttempts
  MissingSignatureHeader
}

// --- Defaults ---

pub fn default_timeout_ms() -> Int {
  5000
}

pub fn default_retry_max_attempts() -> Int {
  3
}

// --- Demo configs ---

pub fn demo_outbound() -> WebhookConfig {
  WebhookConfig(
    name: "demo_outbound_webhook",
    algorithm: HmacSha256,
    delivery_mode: Outbound,
    signature_header: "X-Signature",
    url: "https://webhook.example.test/delivery",
    secret: "demo-secret-key",
    headers: [#("Content-Type", "application/json")],
    timeout_ms: 5000,
    retry_max_attempts: 3,
  )
}

pub fn demo_inbound() -> WebhookConfig {
  WebhookConfig(
    name: "demo_inbound_webhook",
    algorithm: HmacSha256,
    delivery_mode: Inbound,
    signature_header: "X-Signature",
    url: "https://source.example.test/callbacks",
    secret: "demo-secret-key",
    headers: [],
    timeout_ms: 5000,
    retry_max_attempts: 0,
  )
}

// --- Validation ---

/// Validate a WebhookConfig. Checks that required fields are present and
/// values are within reasonable bounds.
///
pub fn validate(config: WebhookConfig) -> Result(WebhookConfig, ConfigError) {
  case config.name {
    "" -> Error(EmptyName)
    _ ->
      case config.url {
        "" -> Error(EmptyUrl)
        _ ->
          case config.secret {
            "" -> Error(EmptySecret)
            _ ->
              case config.signature_header {
                "" -> Error(MissingSignatureHeader)
                _ ->
                  case config.timeout_ms <= 0 {
                    True -> Error(InvalidTimeout)
                    False ->
                      case config.retry_max_attempts < 0 {
                        True -> Error(InvalidRetryAttempts)
                        False -> Ok(config)
                      }
                  }
              }
          }
      }
  }
}

// --- Text helpers ---

pub fn algorithm_text(algorithm: Algorithm) -> String {
  case algorithm {
    HmacSha256 -> "hmac-sha256"
  }
}

pub fn delivery_mode_text(mode: DeliveryMode) -> String {
  case mode {
    Outbound -> "outbound"
    Inbound -> "inbound"
  }
}

/// Produce a human-readable summary of a WebhookConfig.
///
pub fn summary(config: WebhookConfig) -> String {
  config.name
  <> " algorithm="
  <> algorithm_text(config.algorithm)
  <> " mode="
  <> delivery_mode_text(config.delivery_mode)
  <> " url="
  <> config.url
  <> " signature_header="
  <> config.signature_header
  <> " timeout_ms="
  <> int.to_string(config.timeout_ms)
  <> " retry="
  <> int.to_string(config.retry_max_attempts)
  <> " headers="
  <> int.to_string(list.length(config.headers))
}

/// Produce a validation error message suitable for logging or responses.
///
pub fn error_text(error: ConfigError) -> String {
  case error {
    EmptyName -> "webhook name must not be empty"
    EmptyUrl -> "webhook url must not be empty"
    EmptySecret -> "webhook secret must not be empty"
    InvalidTimeout -> "webhook timeout must be > 0"
    InvalidRetryAttempts -> "webhook retry_max_attempts must be >= 0"
    MissingSignatureHeader -> "webhook signature_header must not be empty"
  }
}
