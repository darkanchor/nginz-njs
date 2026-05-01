//// njs entry point for security_gateway. Reads native module variables
//// ($jwt_claim_sub, $oidc_claim_sub, $ratelimit_result, etc.), builds typed
//// signals, evaluates composed policies, and returns allow/deny/challenge.
//// challenge (3xx/401 HTML).

import gleam/int
import gleam/list
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import security_gateway/challenge
import security_gateway/evaluate
import security_gateway/metrics
import security_gateway/model.{
  type SecurityDecision, type SecuritySignal, Allow, Challenge, Deny,
}
import security_gateway/response

/// Evaluate all security signals and return allow (204), deny (4xx), or
fn evaluate_security(r: HTTPRequest) -> Nil {
  let signals = read_signals(r)
  let decision = decide(signals)
  apply_decision(r, decision)
}

/// Evaluate security signals and emit metrics.
fn evaluate_with_metrics(r: HTTPRequest) -> Nil {
  let signals = read_signals(r)
  let decision = decide(signals)
  let route = read_route(r)
  let _ = emit_metric(decision, route)
  apply_decision(r, decision)
}

/// Challenge handler — always issues a challenge response.
fn challenge_handler(r: HTTPRequest) -> Nil {
  let signals = read_signals(r)
  let has_auth =
    list.any(signals, fn(s) {
      case s {
        model.JwtAuthenticated(_) | model.OidcIdentity(_, _, _) -> True
        _ -> False
      }
    })
  case has_auth {
    True -> http.return_code(r, 204)
    False -> {
      let body = challenge.login_redirect("/login")
      let _ = http.set_headers_out(r, "Content-Type", "text/html")
      http.return_text(r, 307, body)
    }
  }
}

// --- Decision logic ---

fn decide(signals: List(SecuritySignal)) -> SecurityDecision {
  let policy =
    evaluate.all_of([
      evaluate.deny_if_rate_limited(),
      evaluate.any_of([
        evaluate.require_jwt(),
        evaluate.require_oidc(),
      ]),
    ])
  evaluate.evaluate(signals, [policy])
}

// --- Signal reading ---

fn read_signals(r: HTTPRequest) -> List(SecuritySignal) {
  let vars = http.get_variables(r)
  [
    read_jwt_signal(vars),
    read_oidc_signal(vars),
    read_ratelimit_signal(vars),
  ]
}

fn read_jwt_signal(vars: JsObject) -> SecuritySignal {
  case ngx.get(vars, "jwt_claim_sub") {
    Ok(v) -> {
      let sub = ngx.to_string(v)
      case sub {
        "" -> model.jwt_anonymous()
        _ -> {
          let claims = read_jwt_claims(vars)
          model.jwt_authenticated(claims)
        }
      }
    }
    Error(_) -> model.jwt_anonymous()
  }
}

fn read_jwt_claims(vars: JsObject) -> List(#(String, String)) {
  let claim_names = ["sub", "role", "email"]
  list.filter_map(claim_names, fn(name) {
    let var_name = "jwt_claim_" <> name
    case ngx.get(vars, var_name) {
      Ok(v) -> Ok(#(name, ngx.to_string(v)))
      Error(_) -> Error(Nil)
    }
  })
}

fn read_oidc_signal(vars: JsObject) -> SecuritySignal {
  case ngx.get(vars, "oidc_claim_sub") {
    Ok(v) -> {
      let sub = ngx.to_string(v)
      case sub {
        "" -> model.oidc_anonymous()
        _ -> {
          let email = case ngx.get(vars, "oidc_claim_email") {
            Ok(e) -> ngx.to_string(e)
            Error(_) -> ""
          }
          let name = case ngx.get(vars, "oidc_claim_name") {
            Ok(n) -> ngx.to_string(n)
            Error(_) -> ""
          }
          model.oidc_identity(sub, email, name)
        }
      }
    }
    Error(_) -> model.oidc_anonymous()
  }
}

fn read_ratelimit_signal(vars: JsObject) -> SecuritySignal {
  let result = case ngx.get(vars, "ratelimit_result") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> "allowed"
  }
  let key = case ngx.get(vars, "ratelimit_key") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let source = case ngx.get(vars, "ratelimit_source") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> "ip"
  }
  case result {
    "denied" -> model.rate_limit(False, key, source)
    _ -> model.rate_limit(True, key, source)
  }
}

fn read_route(r: HTTPRequest) -> String {
  let vars = http.get_variables(r)
  case ngx.get(vars, "uri") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> "/"
  }
}

// --- Response application ---

fn apply_decision(r: HTTPRequest, decision: SecurityDecision) -> Nil {
  case decision {
    Allow -> {
      let _ = http.log(r, "security_gateway: allow")
      http.return_code(r, 204)
    }
    Deny(status: s, reason: rsn) -> {
      let body = case s {
        401 -> response.json_401(rsn)
        403 -> response.json_403(rsn)
        429 -> response.json_429(rsn, 60)
        _ -> response.json_403(rsn)
      }
      let _ = http.set_headers_out(r, "Content-Type", "application/json")
      let _ =
        http.log(r, "security_gateway: deny " <> int.to_string(s) <> " " <> rsn)
      http.return_text(r, s, body)
    }
    Challenge(status: s, reason: rsn, challenge_type: ct) -> {
      let body = challenge.login_redirect("/login")
      let _ = http.set_headers_out(r, "Content-Type", "text/html")
      let _ =
        http.log(
          r,
          "security_gateway: challenge "
            <> int.to_string(s)
            <> " "
            <> ct
            <> " "
            <> rsn,
        )
      http.return_text(r, s, body)
    }
  }
}

fn emit_metric(decision: SecurityDecision, route: String) -> Nil {
  // Metrics emission — the metric value is constructed but actual transport
  // (StatsD UDP, log-phase handler) is a separate concern deferred to Phase 2.
  let _ = metrics.decision_counter(decision, route)
  Nil
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("evaluate_security", evaluate_security)
  |> ngx.merge("evaluate_with_metrics", evaluate_with_metrics)
  |> ngx.merge("challenge_handler", challenge_handler)
}
