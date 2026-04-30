import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import http_client/client
import njs/buffer.{Utf8, from_string}
import njs/headers
import njs/ngx
import njs/request
import njs/response

pub type Response {
  Response(status: Int, body: String)
}

pub type ClientError {
  FetchFailed(reason: String)
  Timeout(timeout_ms: Int)
  InvalidUrl(url: String)
  InvalidRequest(reason: String)
}

/// `execute()` currently emits `FetchFailed` for runtime fetch failures.
/// The other variants are part of the public error model and are intended for
/// future validation and policy layers layered on top of raw execution.
fn build_headers(req: client.Request) -> headers.Headers {
  let base = req.headers
  let with_auth = case req.auth_header {
    Some(value) -> list.append(base, [#("Authorization", value)])
    None -> base
  }
  headers.from_array(array.from_list(with_auth))
}

fn to_runtime_request(req: client.Request) -> request.Request {
  let hdrs = build_headers(req)
  let url = client.build_url(req)
  case req.body {
    Some(body_text) -> {
      let buf = from_string(body_text, Utf8)
      request.from_url(
        url,
        request.RequestOption(
          body: buf,
          headers: hdrs,
          method: client.method_text(req.method),
        ),
      )
    }
    None ->
      request.from_url(
        url,
        request.EmptyRequestOption(
          headers: hdrs,
          method: client.method_text(req.method),
        ),
      )
  }
}

fn fetch_args(req: client.Request) -> ngx.JsObject {
  let opts = ngx.object()
  case req.timeout_ms {
    Some(ms) -> ngx.merge(opts, "timeout", ms)
    None -> opts
  }
}

pub fn execute(req: client.Request) -> Promise(Result(Response, ClientError)) {
  let fetch_promise =
    req
    |> to_runtime_request
    |> ngx.fetch_request(fetch_args(req))
    |> promise.await(fn(resp) {
      use body <- promise.await(response.text(resp))
      promise.resolve(Ok(Response(status: response.status(resp), body: body)))
    })

  promise.rescue(fetch_promise, fn(error) {
    Error(FetchFailed(string.inspect(error)))
  })
}

/// --- Response helpers ---
pub fn is_success(resp: Response) -> Bool {
  resp.status >= 200 && resp.status < 300
}

pub fn is_client_error(resp: Response) -> Bool {
  resp.status >= 400 && resp.status < 500
}

pub fn is_server_error(resp: Response) -> Bool {
  resp.status >= 500 && resp.status < 600
}

pub fn is_redirect(resp: Response) -> Bool {
  resp.status >= 300 && resp.status < 400
}

pub fn status_text(resp: Response) -> String {
  case resp.status {
    200 -> "OK"
    201 -> "Created"
    204 -> "No Content"
    301 -> "Moved Permanently"
    302 -> "Found"
    304 -> "Not Modified"
    400 -> "Bad Request"
    401 -> "Unauthorized"
    403 -> "Forbidden"
    404 -> "Not Found"
    405 -> "Method Not Allowed"
    408 -> "Request Timeout"
    429 -> "Too Many Requests"
    500 -> "Internal Server Error"
    502 -> "Bad Gateway"
    503 -> "Service Unavailable"
    504 -> "Gateway Timeout"
    _ -> ""
  }
}
