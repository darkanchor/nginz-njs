import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import njs/querystring

pub type Method {
  Get
  Head
  Post
  Put
  Patch
  Delete
  Options
}

pub type Request {
  Request(
    method: Method,
    url: String,
    headers: List(#(String, String)),
    auth_header: Option(String),
    body: Option(String),
    query_params: List(#(String, String)),
    timeout_ms: Option(Int),
  )
}

pub type ValidationError {
  EmptyUrl
  InvalidUrl(url: String)
  InvalidTimeout(timeout_ms: Int)
}

pub fn new(url: String) -> Request {
  Request(
    method: Get,
    url: url,
    headers: [],
    auth_header: None,
    body: None,
    query_params: [],
    timeout_ms: None,
  )
}

pub fn with_method(request: Request, method: Method) -> Request {
  Request(..request, method: method)
}

pub fn with_header(request: Request, key: String, value: String) -> Request {
  Request(..request, headers: list.append(request.headers, [#(key, value)]))
}

pub fn with_headers(
  request: Request,
  hdrs: List(#(String, String)),
) -> Request {
  Request(..request, headers: list.append(request.headers, hdrs))
}

pub fn with_bearer_token(request: Request, token: String) -> Request {
  Request(..request, auth_header: Some("Bearer " <> token))
}

pub fn with_body(request: Request, body: String) -> Request {
  Request(..request, body: Some(body))
}

pub fn with_query_param(
  request: Request,
  key: String,
  value: String,
) -> Request {
  Request(
    ..request,
    query_params: list.append(request.query_params, [#(key, value)]),
  )
}

pub fn with_query_params(
  request: Request,
  params: List(#(String, String)),
) -> Request {
  Request(..request, query_params: list.append(request.query_params, params))
}

pub fn with_timeout(request: Request, timeout_ms: Int) -> Request {
  Request(..request, timeout_ms: Some(timeout_ms))
}

pub fn method_text(method: Method) -> String {
  case method {
    Get -> "GET"
    Head -> "HEAD"
    Post -> "POST"
    Put -> "PUT"
    Patch -> "PATCH"
    Delete -> "DELETE"
    Options -> "OPTIONS"
  }
}

pub fn build_url(request: Request) -> String {
  case request.query_params {
    [] -> request.url
    params -> {
      let qs =
        params
        |> list.map(fn(pair) {
          querystring.escape(pair.0) <> "=" <> querystring.escape(pair.1)
        })
        |> string.join("&")
      request.url <> "?" <> qs
    }
  }
}

pub fn validate(request: Request) -> Result(Request, ValidationError) {
  case string.length(request.url) == 0 {
    True -> Error(EmptyUrl)
    False ->
      case request.timeout_ms {
        Some(ms) if ms <= 0 -> Error(InvalidTimeout(ms))
        _ -> validate_url(request)
      }
  }
}

fn validate_url(request: Request) -> Result(Request, ValidationError) {
  case string.split(request.url, "://") {
    [scheme, rest] ->
      case scheme == "http" || scheme == "https" {
        False -> Error(InvalidUrl(request.url))
        True ->
          case
            string.length(rest) > 0
            && !string.starts_with(rest, "/")
            && !string.contains(rest, " ")
          {
            True -> Ok(request)
            False -> Error(InvalidUrl(request.url))
          }
      }
    _ -> Error(InvalidUrl(request.url))
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
  let body_info = case request.body {
    Some(_) -> "some"
    None -> "none"
  }
  let hdr_count = list.length(request.headers)
  let qs = case request.query_params {
    [] -> ""
    params -> " qs=" <> int.to_string(list.length(params)) <> "pairs"
  }
  method_text(request.method)
  <> " "
  <> build_url(request)
  <> " auth="
  <> auth
  <> " timeout_ms="
  <> timeout
  <> " body="
  <> body_info
  <> " headers="
  <> int.to_string(hdr_count)
  <> qs
}

pub fn demo_request() -> Request {
  new("https://example.internal/ping")
  |> with_bearer_token("demo-token")
  |> with_timeout(1500)
}
