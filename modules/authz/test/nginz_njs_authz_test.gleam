import authz/policy.{
  type Context,
  Allow,
  Context,
  Deny,
  all_of,
  any_of,
  evaluate,
  has_claim,
  method_in,
  not_,
  path_prefix,
  require_header,
}
import gleam/dict
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn ctx(method: String, path: String) -> Context {
  Context(
    method: method,
    path: path,
    remote_addr: "127.0.0.1",
    headers: dict.new(),
    claims: dict.new(),
  )
}

pub fn allow_get_test() {
  ctx("GET", "/api")
  |> evaluate([method_in(["GET", "POST"])])
  |> should.equal(Allow)
}

pub fn deny_delete_test() {
  ctx("DELETE", "/api")
  |> evaluate([method_in(["GET", "POST"])])
  |> should.equal(Deny("method not allowed: DELETE"))
}

pub fn path_prefix_allow_test() {
  ctx("GET", "/api/users")
  |> evaluate([path_prefix("/api")])
  |> should.equal(Allow)
}

pub fn path_prefix_deny_test() {
  ctx("GET", "/admin/secret")
  |> evaluate([path_prefix("/api")])
  |> should.equal(Deny("path not allowed: /admin/secret"))
}

pub fn require_header_allow_test() {
  let ctx_h =
    Context(
      ..ctx("GET", "/api"),
      headers: dict.from_list([#("x-api-key", "secret")]),
    )
  ctx_h
  |> evaluate([require_header("x-api-key", "secret")])
  |> should.equal(Allow)
}

pub fn require_header_deny_missing_test() {
  ctx("GET", "/api")
  |> evaluate([require_header("x-api-key", "secret")])
  |> should.equal(Deny("missing required header: x-api-key"))
}

pub fn require_header_deny_mismatch_test() {
  let ctx_h =
    Context(
      ..ctx("GET", "/api"),
      headers: dict.from_list([#("x-api-key", "wrong")]),
    )
  ctx_h
  |> evaluate([require_header("x-api-key", "secret")])
  |> should.equal(Deny("header value mismatch: x-api-key"))
}

pub fn has_claim_allow_test() {
  let ctx_c =
    Context(..ctx("GET", "/api"), claims: dict.from_list([#("role", "admin")]))
  ctx_c
  |> evaluate([has_claim("role", "admin")])
  |> should.equal(Allow)
}

pub fn has_claim_deny_test() {
  ctx("GET", "/api")
  |> evaluate([has_claim("role", "admin")])
  |> should.equal(Deny("missing required claim: role"))
}

pub fn all_of_allow_test() {
  ctx("GET", "/api/users")
  |> evaluate([all_of([method_in(["GET"]), path_prefix("/api")])])
  |> should.equal(Allow)
}

pub fn all_of_deny_first_test() {
  ctx("POST", "/api/users")
  |> evaluate([all_of([method_in(["GET"]), path_prefix("/api")])])
  |> should.equal(Deny("method not allowed: POST"))
}

pub fn all_of_deny_second_test() {
  ctx("GET", "/admin/panel")
  |> evaluate([all_of([method_in(["GET"]), path_prefix("/api")])])
  |> should.equal(Deny("path not allowed: /admin/panel"))
}

pub fn any_of_allow_first_test() {
  ctx("GET", "/private")
  |> evaluate([any_of([method_in(["GET"]), path_prefix("/public")])])
  |> should.equal(Allow)
}

pub fn any_of_allow_second_test() {
  ctx("POST", "/public/file")
  |> evaluate([any_of([method_in(["GET"]), path_prefix("/public")])])
  |> should.equal(Allow)
}

pub fn any_of_deny_none_test() {
  ctx("POST", "/private")
  |> evaluate([any_of([method_in(["GET"]), path_prefix("/public")])])
  |> should.equal(Deny("no rule matched"))
}

pub fn not_rule_test() {
  ctx("DELETE", "/api")
  |> evaluate([not_(method_in(["GET", "POST"]))])
  |> should.equal(Allow)
}

pub fn evaluate_short_circuits_test() {
  ctx("DELETE", "/api")
  |> evaluate([method_in(["GET"]), path_prefix("/anything")])
  |> should.equal(Deny("method not allowed: DELETE"))
}
