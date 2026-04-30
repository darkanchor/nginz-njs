import gleeunit
import gleeunit/should
import http_client/client.{
  Delete, EmptyUrl, Get, Head, InvalidTimeout, InvalidUrl, Options, Post,
  build_url, demo_request, method_text, new, summary, validate,
  with_bearer_token, with_body, with_header, with_headers, with_method,
  with_query_param, with_query_params, with_timeout,
}
import http_client/fetch.{
  Response, is_client_error, is_redirect, is_server_error, is_success,
  status_text,
}
import http_client/middleware
import http_client/policy.{NoRetry, Retry, with_retry}
import http_client/response.{body_if_status, body_if_success, body_or}

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

pub fn build_url_encodes_query_params_test() {
  new("https://api.example.test")
  |> with_query_param("q value", "a&b=c d")
  |> build_url
  |> should.equal("https://api.example.test?q%20value=a%26b%3Dc%20d")
}

// --- Validation ---

pub fn validate_ok_test() {
  new("https://api.example.test")
  |> validate
  |> should.equal(Ok(new("https://api.example.test")))
}

pub fn validate_empty_url_test() {
  new("")
  |> validate
  |> should.equal(Error(EmptyUrl))
}

pub fn validate_invalid_scheme_test() {
  new("ftp://api.example.test")
  |> validate
  |> should.equal(Error(InvalidUrl("ftp://api.example.test")))
}

pub fn validate_missing_host_test() {
  new("https:///oops")
  |> validate
  |> should.equal(Error(InvalidUrl("https:///oops")))
}

pub fn validate_invalid_timeout_test() {
  new("https://api.example.test")
  |> with_timeout(0)
  |> validate
  |> should.equal(Error(InvalidTimeout(0)))
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

// --- Response helpers ---

pub fn is_success_2xx_test() {
  is_success(Response(status: 200, body: "ok"))
  |> should.equal(True)
  is_success(Response(status: 201, body: "created"))
  |> should.equal(True)
  is_success(Response(status: 299, body: ""))
  |> should.equal(True)
  is_success(Response(status: 300, body: ""))
  |> should.equal(False)
  is_success(Response(status: 400, body: ""))
  |> should.equal(False)
  is_success(Response(status: 500, body: ""))
  |> should.equal(False)
}

pub fn is_client_error_4xx_test() {
  is_client_error(Response(status: 400, body: ""))
  |> should.equal(True)
  is_client_error(Response(status: 404, body: ""))
  |> should.equal(True)
  is_client_error(Response(status: 499, body: ""))
  |> should.equal(True)
  is_client_error(Response(status: 200, body: ""))
  |> should.equal(False)
  is_client_error(Response(status: 500, body: ""))
  |> should.equal(False)
}

pub fn is_server_error_5xx_test() {
  is_server_error(Response(status: 500, body: ""))
  |> should.equal(True)
  is_server_error(Response(status: 503, body: ""))
  |> should.equal(True)
  is_server_error(Response(status: 599, body: ""))
  |> should.equal(True)
  is_server_error(Response(status: 200, body: ""))
  |> should.equal(False)
  is_server_error(Response(status: 404, body: ""))
  |> should.equal(False)
}

pub fn is_redirect_3xx_test() {
  is_redirect(Response(status: 301, body: ""))
  |> should.equal(True)
  is_redirect(Response(status: 302, body: ""))
  |> should.equal(True)
  is_redirect(Response(status: 304, body: ""))
  |> should.equal(True)
  is_redirect(Response(status: 200, body: ""))
  |> should.equal(False)
  is_redirect(Response(status: 400, body: ""))
  |> should.equal(False)
}

pub fn status_text_known_codes_test() {
  status_text(Response(status: 200, body: ""))
  |> should.equal("OK")
  status_text(Response(status: 404, body: ""))
  |> should.equal("Not Found")
  status_text(Response(status: 500, body: ""))
  |> should.equal("Internal Server Error")
  status_text(Response(status: 999, body: ""))
  |> should.equal("")
}

// --- Response body helpers ---

pub fn body_or_success_test() {
  body_or(Response(status: 200, body: "hello"), "fallback")
  |> should.equal("hello")
}

pub fn body_or_error_test() {
  body_or(Response(status: 500, body: "error body"), "fallback")
  |> should.equal("fallback")
}

pub fn body_if_success_ok_test() {
  body_if_success(Response(status: 200, body: "hello"))
  |> should.equal(Ok("hello"))
}

pub fn body_if_success_error_test() {
  body_if_success(Response(status: 404, body: "not found"))
  |> should.equal(Error("not found"))
}

pub fn body_if_status_match_test() {
  body_if_status(Response(status: 201, body: "created"), 201)
  |> should.equal(Ok("created"))
}

pub fn body_if_status_mismatch_test() {
  body_if_status(Response(status: 200, body: "ok"), 201)
  |> should.equal(Error("ok"))
}

// --- Policy ---

pub fn policy_default_no_retry_test() {
  let p = policy.new()
  case p {
    policy.Policy(retry: NoRetry) -> Nil
    _ -> should.fail()
  }
}

pub fn policy_with_retry_test() {
  let p = policy.new() |> with_retry(Retry(max_attempts: 5))
  case p {
    policy.Policy(retry: Retry(max_attempts: 5)) -> Nil
    _ -> should.fail()
  }
}

// --- Middleware ---

pub fn middleware_apply_single_test() {
  let req = new("https://api.example.test")
  let mw = middleware.bearer_token("mw-token")
  let result = middleware.apply(req, mw)
  result
  |> summary
  |> should.equal(
    "GET https://api.example.test auth=Bearer mw-token timeout_ms=none body=none headers=0",
  )
}

pub fn middleware_stack_composes_left_to_right_test() {
  let mw =
    middleware.stack([
      middleware.bearer_token("tok"),
      middleware.add_header("X-A", "1"),
      middleware.add_header("X-B", "2"),
      middleware.timeout_ms(999),
    ])
  let req = new("https://api.example.test")
  let result = middleware.apply(req, mw)
  result
  |> summary
  |> should.equal(
    "GET https://api.example.test auth=Bearer tok timeout_ms=999 body=none headers=2",
  )
}

pub fn middleware_json_content_type_test() {
  let mw = middleware.json_content_type()
  let req = new("https://api.example.test")
  let result = middleware.apply(req, mw)
  result
  |> summary
  |> should.equal(
    "GET https://api.example.test auth=none timeout_ms=none body=none headers=1",
  )
}

pub fn middleware_pipeline_idiom_test() {
  // The builder |> pattern and middleware stack produce the same result
  let via_builder =
    new("https://api.example.test")
    |> with_bearer_token("t")
    |> with_header("X-Foo", "bar")
    |> with_timeout(1500)
    |> summary

  let via_middleware =
    new("https://api.example.test")
    |> middleware.apply(
      middleware.stack([
        middleware.bearer_token("t"),
        middleware.add_header("X-Foo", "bar"),
        middleware.timeout_ms(1500),
      ]),
    )
    |> summary

  via_builder |> should.equal(via_middleware)
}
