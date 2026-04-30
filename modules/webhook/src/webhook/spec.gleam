pub type Algorithm {
  HmacSha256
}

pub type DeliveryMode {
  Outbound
  Inbound
}

pub type WebhookConfig {
  WebhookConfig(
    name: String,
    algorithm: Algorithm,
    delivery_mode: DeliveryMode,
    signature_header: String,
  )
}

pub fn demo_outbound() -> WebhookConfig {
  WebhookConfig(
    name: "demo_outbound_webhook",
    algorithm: HmacSha256,
    delivery_mode: Outbound,
    signature_header: "X-Signature",
  )
}

pub fn demo_inbound() -> WebhookConfig {
  WebhookConfig(
    name: "demo_inbound_webhook",
    algorithm: HmacSha256,
    delivery_mode: Inbound,
    signature_header: "X-Signature",
  )
}

fn algorithm_text(algorithm: Algorithm) -> String {
  case algorithm {
    HmacSha256 -> "hmac-sha256"
  }
}

fn delivery_mode_text(mode: DeliveryMode) -> String {
  case mode {
    Outbound -> "outbound"
    Inbound -> "inbound"
  }
}

pub fn summary(config: WebhookConfig) -> String {
  config.name
  <> " algorithm="
  <> algorithm_text(config.algorithm)
  <> " mode="
  <> delivery_mode_text(config.delivery_mode)
  <> " signature_header="
  <> config.signature_header
}
