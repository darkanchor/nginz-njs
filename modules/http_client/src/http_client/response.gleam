import http_client/fetch.{type Response, is_success}

/// Return the body if the status is a 2xx success, otherwise return
/// `default`.
///
pub fn body_or(resp: Response, on_error: String) -> String {
  case is_success(resp) {
    True -> resp.body
    False -> on_error
  }
}

/// Return `Ok(body)` for 2xx responses, `Error(body)` otherwise.
///
pub fn body_if_success(resp: Response) -> Result(String, String) {
  case is_success(resp) {
    True -> Ok(resp.body)
    False -> Error(resp.body)
  }
}

/// Return `Ok(body)` for responses with the given status code,
/// `Error(body)` otherwise.
///
pub fn body_if_status(resp: Response, expected: Int) -> Result(String, String) {
  case resp.status == expected {
    True -> Ok(resp.body)
    False -> Error(resp.body)
  }
}
