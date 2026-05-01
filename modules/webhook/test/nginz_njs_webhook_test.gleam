import gleam/javascript/promise.{type Promise}
import gleam/string
import gleeunit
import gleeunit/should
import webhook/deliver.{type DeliveryError, ConfigInvalid, SignFailed}
import webhook/sign
import webhook/spec
import webhook/verify.{InvalidSignature, MissingSignature}

pub fn main() {
  gleeunit.main()
}

// --- Spec: summary ---

pub fn outbound_summary_test() {
  spec.demo_outbound()
  |> spec.summary
  |> should.equal(
    "demo_outbound_webhook algorithm=hmac-sha256 mode=outbound url=https://webhook.example.test/delivery signature_header=X-Signature timeout_ms=5000 retry=3 headers=1",
  )
}

pub fn inbound_summary_test() {
  spec.demo_inbound()
  |> spec.summary
  |> should.equal(
    "demo_inbound_webhook algorithm=hmac-sha256 mode=inbound url=https://source.example.test/callbacks signature_header=X-Signature timeout_ms=5000 retry=0 headers=0",
  )
}

// --- Spec: validation ---

pub fn validate_ok_test() {
  spec.validate(spec.demo_outbound())
  |> should.be_ok()
}

pub fn validate_empty_name_test() {
  let c = spec.WebhookConfig(..spec.demo_outbound(), name: "")
  spec.validate(c)
  |> should.equal(Error(spec.EmptyName))
}

pub fn validate_empty_url_test() {
  let c = spec.WebhookConfig(..spec.demo_outbound(), url: "")
  spec.validate(c)
  |> should.equal(Error(spec.EmptyUrl))
}

pub fn validate_empty_secret_test() {
  let c = spec.WebhookConfig(..spec.demo_outbound(), secret: "")
  spec.validate(c)
  |> should.equal(Error(spec.EmptySecret))
}

pub fn validate_invalid_timeout_test() {
  let c = spec.WebhookConfig(..spec.demo_outbound(), timeout_ms: 0)
  spec.validate(c)
  |> should.equal(Error(spec.InvalidTimeout))
}

pub fn validate_missing_signature_header_test() {
  let c = spec.WebhookConfig(..spec.demo_outbound(), signature_header: "")
  spec.validate(c)
  |> should.equal(Error(spec.MissingSignatureHeader))
}

pub fn validate_invalid_retry_test() {
  let c = spec.WebhookConfig(..spec.demo_outbound(), retry_max_attempts: -1)
  spec.validate(c)
  |> should.equal(Error(spec.InvalidRetryAttempts))
}

// --- Spec: error_text ---

pub fn error_text_empty_name_test() {
  spec.error_text(spec.EmptyName)
  |> should.equal("webhook name must not be empty")
}

pub fn error_text_empty_secret_test() {
  spec.error_text(spec.EmptySecret)
  |> should.equal("webhook secret must not be empty")
}

// --- Sign: deterministic HMAC ---

pub fn sign_produces_hex_test() -> Promise(Nil) {
  let config = spec.demo_outbound()
  let payload = "hello webhook"
  sign.sign(config, payload)
  |> promise.map(fn(sig) {
    sig
    |> string.length
    |> should.equal(64)
  })
}

pub fn sign_same_input_same_output_test() -> Promise(Nil) {
  let config = spec.demo_outbound()
  let payload = "consistent payload"
  use sig1 <- promise.await(sign.sign(config, payload))
  sign.sign(config, payload)
  |> promise.map(fn(sig2) { sig1 |> should.equal(sig2) })
}

pub fn sign_different_payload_different_output_test() -> Promise(Nil) {
  let config = spec.demo_outbound()
  use sig1 <- promise.await(sign.sign(config, "payload A"))
  sign.sign(config, "payload B")
  |> promise.map(fn(sig2) { sig1 |> should.not_equal(sig2) })
}

// --- Sign: verify round-trip ---

pub fn verify_valid_signature_test() -> Promise(Nil) {
  let config = spec.demo_outbound()
  let payload = "test payload"
  use sig <- promise.await(sign.sign(config, payload))
  sign.verify(config, payload, sig)
  |> promise.map(fn(valid) { valid |> should.be_true() })
}

pub fn verify_wrong_payload_test() -> Promise(Nil) {
  let config = spec.demo_outbound()
  use sig <- promise.await(sign.sign(config, "original"))
  sign.verify(config, "tampered", sig)
  |> promise.map(fn(valid) { valid |> should.be_false() })
}

pub fn verify_wrong_secret_test() -> Promise(Nil) {
  let config = spec.demo_outbound()
  let alt = spec.WebhookConfig(..config, secret: "wrong-secret")
  let payload = "test"
  use sig <- promise.await(sign.sign(config, payload))
  sign.verify(alt, payload, sig)
  |> promise.map(fn(valid) { valid |> should.be_false() })
}

pub fn verify_empty_signature_test() -> Promise(Nil) {
  let config = spec.demo_outbound()
  sign.verify(config, "test", "")
  |> promise.map(fn(valid) { valid |> should.be_false() })
}

pub fn verify_case_insensitive_test() -> Promise(Nil) {
  let config = spec.demo_outbound()
  let payload = "test"
  use sig <- promise.await(sign.sign(config, payload))
  let upper = string.uppercase(sig)
  sign.verify(config, payload, upper)
  |> promise.map(fn(valid) { valid |> should.be_true() })
}

// --- Sign: signature_header ---

pub fn signature_header_builds_correctly_test() {
  let config = spec.demo_outbound()
  let #(name, value) = sign.signature_header(config, "abc123")
  name |> should.equal("X-Signature")
  value |> should.equal("abc123")
}

// --- Verify: extract_signature ---

pub fn extract_signature_found_test() {
  let config = spec.demo_outbound()
  let headers = [
    #("Content-Type", "application/json"),
    #("X-Signature", "abc123"),
  ]
  verify.extract_signature(headers, config)
  |> should.equal(Ok("abc123"))
}

pub fn extract_signature_missing_test() {
  let config = spec.demo_outbound()
  let headers = [#("Content-Type", "application/json")]
  verify.extract_signature(headers, config)
  |> should.equal(Error(MissingSignature("X-Signature")))
}

pub fn extract_signature_case_insensitive_test() {
  let config = spec.demo_outbound()
  let headers = [#("x-signature", "abc123")]
  verify.extract_signature(headers, config)
  |> should.equal(Ok("abc123"))
}

// --- Verify: verify_request ---

pub fn verify_request_valid_test() -> Promise(Nil) {
  let config = spec.demo_outbound()
  let payload = "webhook body"
  use sig <- promise.await(sign.sign(config, payload))
  let headers = [#(config.signature_header, sig)]
  verify.verify_request(headers, payload, config)
  |> promise.map(fn(result) { result |> should.be_ok() })
}

pub fn verify_request_invalid_signature_test() -> Promise(Nil) {
  let config = spec.demo_outbound()
  let payload = "webhook body"
  let headers = [#("X-Signature", "bad-sig")]
  verify.verify_request(headers, payload, config)
  |> promise.map(fn(result) {
    result |> should.equal(Error(InvalidSignature("X-Signature", "bad-sig")))
  })
}

pub fn verify_request_missing_header_test() -> Promise(Nil) {
  let config = spec.demo_outbound()
  let payload = "webhook body"
  let headers = []
  verify.verify_request(headers, payload, config)
  |> promise.map(fn(result) {
    result |> should.equal(Error(MissingSignature("X-Signature")))
  })
}

// --- DeliveryError discriminators ---

pub fn delivery_error_config_invalid_test() {
  case ConfigInvalid("bad") |> is_config_invalid {
    True -> Nil
    False -> should.fail()
  }
}

pub fn delivery_error_sign_failed_not_config_invalid_test() {
  case SignFailed("oops") |> is_config_invalid {
    False -> Nil
    True -> should.fail()
  }
}

fn is_config_invalid(err: DeliveryError) -> Bool {
  case err {
    ConfigInvalid(_) -> True
    _ -> False
  }
}
