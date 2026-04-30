import gleam/javascript/promise.{type Promise}
import http_client/client
import http_client/fetch.{type ClientError, type Response, execute}

/// Retry strategy. Only immediate retry (no delay) is supported because njs
/// timer callbacks run outside request context and break `ngx.fetch()`.
/// Backoff-delay retry requires a native primitive.
///
pub type RetryPolicy {
  NoRetry
  Retry(max_attempts: Int)
}

/// A composed execution policy combining retry behaviour with the timeout
/// that is already carried on the `Request` record. The timeout is enforced
/// by `ngx.fetch()` options; this policy wrapper just ensures the value is
/// present on the request before execution.
///
pub type Policy {
  Policy(retry: RetryPolicy)
}

pub fn new() -> Policy {
  Policy(retry: NoRetry)
}

pub fn with_retry(_policy: Policy, retry: RetryPolicy) -> Policy {
  Policy(retry: retry)
}

/// Execute a request with a policy. Retry re-runs `execute()` immediately
/// (no backoff delay) up to `max_attempts` times on any `ClientError`.
///
pub fn execute_with_policy(
  req: client.Request,
  policy: Policy,
) -> Promise(Result(Response, ClientError)) {
  case policy.retry {
    NoRetry -> execute(req)
    Retry(max) if max <= 1 -> execute(req)
    Retry(max) -> attempt(req, max, 1)
  }
}

fn attempt(
  req: client.Request,
  max_attempts: Int,
  attempt_num: Int,
) -> Promise(Result(Response, ClientError)) {
  use result <- promise.await(execute(req))
  case result {
    Ok(_) -> promise.resolve(result)
    Error(_) if attempt_num < max_attempts ->
      attempt(req, max_attempts, attempt_num + 1)
    Error(_) -> promise.resolve(result)
  }
}
