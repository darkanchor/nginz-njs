import gleam/int
import gleam/option.{type Option, None, Some}

pub type Method {
  Get
  Post
  Put
  Patch
  Delete
}

pub type Request {
  Request(
    method: Method,
    url: String,
    auth_header: Option(String),
    timeout_ms: Option(Int),
  )
}

pub fn new(url: String) -> Request {
  Request(method: Get, url: url, auth_header: None, timeout_ms: None)
}

pub fn with_method(request: Request, method: Method) -> Request {
  Request(..request, method: method)
}

pub fn with_bearer_token(request: Request, token: String) -> Request {
  Request(..request, auth_header: Some("Bearer " <> token))
}

pub fn with_timeout(request: Request, timeout_ms: Int) -> Request {
  Request(..request, timeout_ms: Some(timeout_ms))
}

pub fn method_text(method: Method) -> String {
  case method {
    Get -> "GET"
    Post -> "POST"
    Put -> "PUT"
    Patch -> "PATCH"
    Delete -> "DELETE"
  }
}

pub fn summary(request: Request) -> String {
  let auth = case request.auth_header {
    Some(value) -> value
    None -> "none"
  }
  let timeout = case request.timeout_ms {
    Some(value) -> int.to_string(value)
    None -> "none"
  }
  method_text(request.method)
  <> " "
  <> request.url
  <> " auth="
  <> auth
  <> " timeout_ms="
  <> timeout
}

pub fn demo_request() -> Request {
  new("https://example.internal/ping")
  |> with_bearer_token("demo-token")
  |> with_timeout(1500)
}
