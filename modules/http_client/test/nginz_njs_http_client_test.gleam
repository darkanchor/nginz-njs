import gleeunit
import gleeunit/should
import http_client/client.{
  Post, demo_request, new, summary, with_bearer_token, with_method, with_timeout,
}

pub fn main() {
  gleeunit.main()
}

pub fn new_request_defaults_test() {
  new("https://api.example.test")
  |> summary
  |> should.equal("GET https://api.example.test auth=none timeout_ms=none")
}

pub fn request_builder_pipeline_test() {
  new("https://api.example.test")
  |> with_method(Post)
  |> with_bearer_token("secret-token")
  |> with_timeout(2500)
  |> summary
  |> should.equal(
    "POST https://api.example.test auth=Bearer secret-token timeout_ms=2500",
  )
}

pub fn demo_request_summary_test() {
  demo_request()
  |> summary
  |> should.equal(
    "GET https://example.internal/ping auth=Bearer demo-token timeout_ms=1500",
  )
}
