import gleeunit
import gleeunit/should
import webhook/spec

pub fn main() {
  gleeunit.main()
}

pub fn outbound_summary_test() {
  spec.demo_outbound()
  |> spec.summary
  |> should.equal(
    "demo_outbound_webhook algorithm=hmac-sha256 mode=outbound signature_header=X-Signature",
  )
}

pub fn inbound_summary_test() {
  spec.demo_inbound()
  |> spec.summary
  |> should.equal(
    "demo_inbound_webhook algorithm=hmac-sha256 mode=inbound signature_header=X-Signature",
  )
}
