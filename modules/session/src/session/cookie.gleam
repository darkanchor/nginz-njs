import gleam/int
import gleam/list
import gleam/string
import session/model.{type CookieConfig}

/// Build a Set-Cookie header value for the given session ID and TTL.
pub fn set_header(
  config: CookieConfig,
  session_id: String,
  ttl_s: Int,
) -> String {
  let base =
    config.name
    <> "="
    <> session_id
    <> "; Max-Age="
    <> int.to_string(ttl_s)
    <> "; Path="
    <> config.path
    <> "; SameSite="
    <> config.same_site
  let with_http_only = case config.http_only {
    True -> base <> "; HttpOnly"
    False -> base
  }
  case config.secure {
    True -> with_http_only <> "; Secure"
    False -> with_http_only
  }
}

/// Build a Set-Cookie header value that expires the session cookie immediately.
pub fn clear_header(config: CookieConfig) -> String {
  config.name <> "=; Max-Age=0; Path=" <> config.path
}

/// Extract the named cookie value from a Cookie request header.
/// Handles `"name1=val1; name2=val2"` format.
pub fn read_id(cookie_header: String, name: String) -> Result(String, Nil) {
  cookie_header
  |> string.split("; ")
  |> list.find_map(fn(pair) {
    case string.split_once(pair, "=") {
      Ok(#(k, v)) ->
        case k == name {
          True -> Ok(v)
          False -> Error(Nil)
        }
      Error(_) -> Error(Nil)
    }
  })
}
