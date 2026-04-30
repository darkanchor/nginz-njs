import gleam/list
import http_client/client.{type Request}

/// A middleware is a pure function that transforms a `Request`.
/// Compose multiple middlewares with `stack` to build reusable request
/// pipelines.
///
pub type Middleware =
  fn(Request) -> Request

/// Apply a single middleware to a request.
///
pub fn apply(req: Request, mw: Middleware) -> Request {
  mw(req)
}

/// Compose a list of middlewares into a single middleware. The first
/// middleware in the list is applied first (left-to-right).
///
pub fn stack(mws: List(Middleware)) -> Middleware {
  fn(req: Request) -> Request { list.fold(mws, req, fn(r, mw) { mw(r) }) }
}

/// --- Pre-built middlewares ---
/// Inject a bearer token into the request's auth header.
///
pub fn bearer_token(token: String) -> Middleware {
  fn(req: Request) -> Request { client.with_bearer_token(req, token) }
}

/// Add a single header.
///
pub fn add_header(key: String, value: String) -> Middleware {
  fn(req: Request) -> Request { client.with_header(req, key, value) }
}

/// Set the Content-Type header to `application/json`.
///
pub fn json_content_type() -> Middleware {
  add_header("Content-Type", "application/json")
}

/// Set the request timeout.
///
pub fn timeout_ms(ms: Int) -> Middleware {
  fn(req: Request) -> Request { client.with_timeout(req, ms) }
}
