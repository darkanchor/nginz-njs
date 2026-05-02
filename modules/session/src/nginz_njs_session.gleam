import gleam/int
import gleam/javascript/promise.{type Promise}
import njs/buffer.{Hex, Utf8, from_string}
import njs/crypto
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import session/assignment
import session/cookie
import session/identity
import session/model
import session/store

fn describe(r: HTTPRequest) -> Nil {
  model.default_descriptor()
  |> model.summary
  |> http.return_text(r, 200, _)
}

/// Create a new session for the authenticated subject set in $session_subject.
/// Reads $session_dict and $session_ttl (default 3600) from nginx variables.
/// Generates a SHA-256 session ID from the current timestamp and remote address.
/// Sets Set-Cookie on the response and returns 204.
fn start(r: HTTPRequest) -> Promise(Nil) {
  let vars = http.get_variables(r)
  let dict_name = case ngx.get(vars, "session_dict") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  case dict_name {
    "" -> {
      http.return_code(r, 500)
      promise.resolve(Nil)
    }
    dict -> {
      let ttl_s = case ngx.get(vars, "session_ttl") {
        Ok(v) ->
          case int.parse(ngx.to_string(v)) {
            Ok(n) -> n
            Error(_) -> 3600
          }
        Error(_) -> 3600
      }
      let subject = case ngx.get(vars, "session_subject") {
        Ok(v) -> ngx.to_string(v)
        Error(_) -> http.remote_address(r)
      }
      let descriptor = model.default_descriptor()
      let seed = int.to_string(ngx.now()) <> ":" <> http.remote_address(r)
      use sid <- promise.await(
        seed |> from_string(Utf8) |> crypto.compute_hash("sha256", _, Hex),
      )
      store.save(dict, sid, subject, ttl_s)
      let _ =
        http.set_headers_out(
          r,
          "Set-Cookie",
          cookie.set_header(descriptor.cookie, sid, ttl_s),
        )
      http.return_code(r, 204)
      promise.resolve(Nil)
    }
  }
}

/// Verify an incoming session cookie. Reads $session_dict from nginx variables.
/// Returns 204 + X-Session-Subject on success, 401 when the session is absent
/// or expired. Designed for use with nginx auth_request.
fn verify(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let dict_name = case ngx.get(vars, "session_dict") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let descriptor = model.default_descriptor()
  case http.get_header_in(r, "cookie") {
    Error(_) -> http.return_code(r, 401)
    Ok(cookie_header) ->
      case cookie.read_id(cookie_header, descriptor.cookie.name) {
        Error(_) -> http.return_code(r, 401)
        Ok(sid) ->
          case dict_name {
            "" -> http.return_code(r, 500)
            dict ->
              case store.load(dict, sid) {
                Error(_) -> http.return_code(r, 401)
                Ok(subject) -> {
                  let _ = http.set_headers_out(r, "X-Session-Subject", subject)
                  http.return_code(r, 204)
                }
              }
          }
      }
  }
}

/// Invalidate the session identified by the incoming cookie and clear it on
/// the client. Always returns 204 regardless of whether a session existed.
fn end_session(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let dict_name = case ngx.get(vars, "session_dict") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let descriptor = model.default_descriptor()
  let _ = case http.get_header_in(r, "cookie") {
    Error(_) -> Nil
    Ok(cookie_header) ->
      case cookie.read_id(cookie_header, descriptor.cookie.name) {
        Error(_) -> Nil
        Ok(sid) ->
          case dict_name {
            "" -> Nil
            dict -> {
              store.delete(dict, sid)
              assignment.delete_canary(dict, sid)
            }
          }
      }
  }
  let _ =
    http.set_headers_out(
      r,
      "Set-Cookie",
      cookie.clear_header(descriptor.cookie),
    )
  http.return_code(r, 204)
}

/// Read the sticky canary assignment for the current session.
/// Returns "1" (canary) or "0" (stable), or 404 when no assignment is stored.
fn get_canary(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let dict_name = case ngx.get(vars, "session_dict") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let descriptor = model.default_descriptor()
  case http.get_header_in(r, "cookie") {
    Error(_) -> http.return_code(r, 404)
    Ok(cookie_header) ->
      case cookie.read_id(cookie_header, descriptor.cookie.name) {
        Error(_) -> http.return_code(r, 404)
        Ok(sid) ->
          case dict_name {
            "" -> http.return_code(r, 500)
            dict ->
              case assignment.load_canary(dict, sid) {
                assignment.Unassigned -> http.return_code(r, 404)
                assignment.Assigned(b) ->
                  http.return_text(r, 200, assignment.canary_to_string(b))
              }
          }
      }
  }
}

/// Create a session from a validated OIDC subject ($oidc_claim_sub).
/// Called in the content phase after the oidc native module has run access-phase validation.
/// Normalizes the subject to "oidc:{sub}", stores it, sets Set-Cookie; returns 204.
/// Returns 401 when the OIDC module provides an empty subject.
fn start_oidc(r: HTTPRequest) -> Promise(Nil) {
  let vars = http.get_variables(r)
  let dict_name = case ngx.get(vars, "session_dict") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  case dict_name {
    "" -> {
      http.return_code(r, 500)
      promise.resolve(Nil)
    }
    dict -> {
      let ttl_s = case ngx.get(vars, "session_ttl") {
        Ok(v) ->
          case int.parse(ngx.to_string(v)) {
            Ok(n) -> n
            Error(_) -> 3600
          }
        Error(_) -> 3600
      }
      let raw_sub = case ngx.get(vars, "oidc_claim_sub") {
        Ok(v) -> ngx.to_string(v)
        Error(_) -> ""
      }
      case identity.from_oidc_sub(raw_sub) {
        Error(_) -> {
          http.return_code(r, 401)
          promise.resolve(Nil)
        }
        Ok(subject) -> {
          let descriptor = model.default_descriptor()
          let seed = int.to_string(ngx.now()) <> ":" <> http.remote_address(r)
          use sid <- promise.await(
            seed |> from_string(Utf8) |> crypto.compute_hash("sha256", _, Hex),
          )
          store.save(dict, sid, subject, ttl_s)
          let _ =
            http.set_headers_out(
              r,
              "Set-Cookie",
              cookie.set_header(descriptor.cookie, sid, ttl_s),
            )
          http.return_code(r, 204)
          promise.resolve(Nil)
        }
      }
    }
  }
}

/// Persist a sticky canary assignment for the current session.
/// Reads $session_dict, $session_canary ("1" or "0"), $session_ttl from nginx vars.
fn set_canary(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let dict_name = case ngx.get(vars, "session_dict") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let descriptor = model.default_descriptor()
  case http.get_header_in(r, "cookie") {
    Error(_) -> http.return_code(r, 400)
    Ok(cookie_header) ->
      case cookie.read_id(cookie_header, descriptor.cookie.name) {
        Error(_) -> http.return_code(r, 400)
        Ok(sid) ->
          case dict_name {
            "" -> http.return_code(r, 500)
            dict -> {
              let ttl_s = case ngx.get(vars, "session_ttl") {
                Ok(v) ->
                  case int.parse(ngx.to_string(v)) {
                    Ok(n) -> n
                    Error(_) -> 3600
                  }
                Error(_) -> 3600
              }
              let canary_val = case ngx.get(vars, "session_canary") {
                Ok(v) -> ngx.to_string(v) == "1"
                Error(_) -> False
              }
              assignment.save_canary(dict, sid, canary_val, ttl_s)
              http.return_code(r, 204)
            }
          }
      }
  }
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
  |> ngx.merge("start", start)
  |> ngx.merge("start_oidc", start_oidc)
  |> ngx.merge("verify", verify)
  |> ngx.merge("end_session", end_session)
  |> ngx.merge("get_canary", get_canary)
  |> ngx.merge("set_canary", set_canary)
}
