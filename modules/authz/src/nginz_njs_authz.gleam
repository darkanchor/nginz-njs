import authz/policy.{type Context, Allow, Context, Deny}
import gleam/dict
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn context_from_request(r: HTTPRequest) -> Context {
  Context(
    method: http.method(r),
    path: http.uri(r),
    remote_addr: http.remote_address(r),
    headers: http.headers_in(r),
    claims: dict.new(),
  )
}

fn check(r: HTTPRequest) -> Nil {
  let ctx = context_from_request(r)
  let rules = [
    policy.method_in(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]),
  ]
  case policy.evaluate(ctx, rules) {
    Allow -> http.return_code(r, 204)
    Deny(reason) -> {
      let _ = http.log(r, "authz: denied — " <> reason)
      http.return_code(r, 403)
    }
  }
}

fn jwt_check(r: HTTPRequest) -> Nil {
  let vars = http.get_variables(r)
  let role = case ngx.get(vars, "jwt_claim_role") {
    Ok(v) -> ngx.to_string(v)
    Error(_) -> ""
  }
  let claims = dict.from_list([#("role", role)])
  let ctx = Context(..context_from_request(r), claims: claims)
  let rules = [
    policy.any_of([
      policy.has_claim("role", "admin"),
      policy.has_claim("role", "user"),
    ]),
  ]
  case policy.evaluate(ctx, rules) {
    Allow -> http.return_code(r, 204)
    Deny(reason) -> {
      let _ = http.log(r, "authz: jwt denied — " <> reason)
      http.return_code(r, 403)
    }
  }
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("check", check)
  |> ngx.merge("jwt_check", jwt_check)
}
