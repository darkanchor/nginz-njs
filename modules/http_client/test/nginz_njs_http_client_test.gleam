import gleeunit
import gleeunit/should
import http_client/client.{
  Delete, Get, Head, Options, Post, build_url, demo_request, method_text, new,
  summary, with_bearer_token, with_body, with_header, with_headers, with_method,
  with_query_param, with_query_params, with_timeout,
}

pub fn main() {
  gleeunit.main()
}

// --- Defaults ---

pub fn new_request_defaults_test() {
  new("https://api.example.test")
  |> summary
  |> should.equal(
    "GET https://api.example.test auth=none timeout_ms=none body=none headers=0",
  )
}

// --- Basic builder pipeline (backward compat) ---

pub fn request_builder_pipeline_test() {
  new("https://api.example.test")
  |> with_method(Post)
  |> with_bearer_token("secret-token")
  |> with_timeout(2500)
  |> summary
  |> should.equal(
    "POST https://api.example.test auth=Bearer secret-token timeout_ms=2500 body=none headers=0",
  )
}

pub fn demo_request_summary_test() {
  demo_request()
  |> summary
  |> should.equal(
    "GET https://example.internal/ping auth=Bearer demo-token timeout_ms=1500 body=none headers=0",
  )
}

// --- method_text ---

pub fn method_text_all_variants_test() {
  method_text(Get)
  |> should.equal("GET")
  method_text(Head)
  |> should.equal("HEAD")
  method_text(Post)
  |> should.equal("POST")
  method_text(Options)
  |> should.equal("OPTIONS")
  method_text(Delete)
  |> should.equal("DELETE")
}

// --- Headers ---

pub fn single_header_test() {
  new("https://api.example.test")
  |> with_header("Content-Type", "application/json")
  |> summary
  |> should.equal(
    "GET https://api.example.test auth=none timeout_ms=none body=none headers=1",
  )
}

pub fn multiple_headers_test() {
  new("https://api.example.test")
  |> with_header("Content-Type", "application/json")
  |> with_header("X-Request-Id", "abc-123")
  |> summary
  |> should.equal(
    "GET https://api.example.test auth=none timeout_ms=none body=none headers=2",
  )
}

pub fn with_headers_bulk_test() {
  new("https://api.example.test")
  |> with_headers([
    #("Accept", "application/json"),
    #("X-Trace-Id", "trace-1"),
    #("X-Span-Id", "span-2"),
  ])
  |> summary
  |> should.equal(
    "GET https://api.example.test auth=none timeout_ms=none body=none headers=3",
  )
}

pub fn headers_and_auth_combined_test() {
  new("https://api.example.test")
  |> with_header("Content-Type", "application/json")
  |> with_bearer_token("secret-token")
  |> summary
  |> should.equal(
    "GET https://api.example.test auth=Bearer secret-token timeout_ms=none body=none headers=1",
  )
}

// --- Body ---

pub fn request_with_body_test() {
  new("https://api.example.test")
  |> with_body("{\"key\": \"value\"}")
  |> summary
  |> should.equal(
    "GET https://api.example.test auth=none timeout_ms=none body=some headers=0",
  )
}

pub fn post_with_body_test() {
  new("https://api.example.test")
  |> with_method(Post)
  |> with_body("hello world")
  |> summary
  |> should.equal(
    "POST https://api.example.test auth=none timeout_ms=none body=some headers=0",
  )
}

// --- Query params ---

pub fn single_query_param_test() {
  new("https://api.example.test")
  |> with_query_param("page", "1")
  |> summary
  |> should.equal(
    "GET https://api.example.test?page=1 auth=none timeout_ms=none body=none headers=0 qs=1pairs",
  )
}

pub fn multiple_query_params_test() {
  new("https://api.example.test")
  |> with_query_param("page", "1")
  |> with_query_param("limit", "20")
  |> summary
  |> should.equal(
    "GET https://api.example.test?page=1&limit=20 auth=none timeout_ms=none body=none headers=0 qs=2pairs",
  )
}

pub fn with_query_params_bulk_test() {
  new("https://api.example.test")
  |> with_query_params([#("a", "1"), #("b", "2"), #("c", "3")])
  |> summary
  |> should.equal(
    "GET https://api.example.test?a=1&b=2&c=3 auth=none timeout_ms=none body=none headers=0 qs=3pairs",
  )
}

// --- build_url ---

pub fn build_url_no_params_test() {
  new("https://api.example.test")
  |> build_url
  |> should.equal("https://api.example.test")
}

pub fn build_url_with_params_test() {
  new("https://api.example.test")
  |> with_query_param("q", "hello")
  |> with_query_param("t", "world")
  |> build_url
  |> should.equal("https://api.example.test?q=hello&t=world")
}

// --- Full pipeline ---

pub fn full_pipeline_test() {
  new("https://api.example.test/users")
  |> with_method(Post)
  |> with_header("Content-Type", "application/json")
  |> with_header("X-Request-Id", "req-001")
  |> with_bearer_token("secret-token")
  |> with_body("{\"name\": \"test\"}")
  |> with_query_param("page", "1")
  |> with_query_param("limit", "20")
  |> with_query_param("sort", "desc")
  |> with_timeout(5000)
  |> summary
  |> should.equal(
    "POST https://api.example.test/users?page=1&limit=20&sort=desc auth=Bearer secret-token timeout_ms=5000 body=some headers=2 qs=3pairs",
  )
}

// --- Immutability: builder does not mutate the original ---

pub fn builder_immutability_test() {
  let req = new("https://api.example.test")
  let _modified = req |> with_header("X-Extra", "value")
  req
  |> summary
  |> should.equal(
    "GET https://api.example.test auth=none timeout_ms=none body=none headers=0",
  )
}
