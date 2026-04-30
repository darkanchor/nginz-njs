import authz/policy.{
  type Context, Allow, Context, Deny, all_of, any_of, async_evaluate,
  claim_contains, claim_contains_one_of, claim_one_of, evaluate, has_claim,
  header_one_of, method_in, not_, path_prefix, query_param, query_param_one_of,
  require_header, to_async,
}
import gleam/dict
import gleam/javascript/promise
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
    query: dict.new(),
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

pub fn claim_one_of_allow_test() {
  let ctx_c =
    Context(..ctx("GET", "/api"), claims: dict.from_list([#("role", "user")]))
  ctx_c
  |> evaluate([claim_one_of("role", ["admin", "user"])])
  |> should.equal(Allow)
}

pub fn claim_one_of_deny_missing_test() {
  ctx("GET", "/api")
  |> evaluate([claim_one_of("role", ["admin", "user"])])
  |> should.equal(Deny("missing required claim: role"))
}

pub fn claim_one_of_deny_mismatch_test() {
  let ctx_c =
    Context(..ctx("GET", "/api"), claims: dict.from_list([#("role", "guest")]))
  ctx_c
  |> evaluate([claim_one_of("role", ["admin", "user"])])
  |> should.equal(Deny("claim value mismatch: role"))
}

pub fn header_one_of_allow_test() {
  let ctx_h =
    Context(
      ..ctx("GET", "/api"),
      headers: dict.from_list([#("x-role", "internal")]),
    )
  ctx_h
  |> evaluate([header_one_of("x-role", ["internal", "partner"])])
  |> should.equal(Allow)
}

pub fn header_one_of_deny_missing_test() {
  ctx("GET", "/api")
  |> evaluate([header_one_of("x-role", ["internal", "partner"])])
  |> should.equal(Deny("missing required header: x-role"))
}

pub fn header_one_of_deny_mismatch_test() {
  let ctx_h =
    Context(
      ..ctx("GET", "/api"),
      headers: dict.from_list([#("x-role", "external")]),
    )
  ctx_h
  |> evaluate([header_one_of("x-role", ["internal", "partner"])])
  |> should.equal(Deny("header value mismatch: x-role"))
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

pub fn all_of_with_claim_one_of_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api/users"),
      claims: dict.from_list([#("role", "user")]),
    )
  ctx_c
  |> evaluate([
    all_of([path_prefix("/api"), claim_one_of("role", ["admin", "user"])]),
  ])
  |> should.equal(Allow)
}

pub fn any_of_with_header_one_of_test() {
  let ctx_h =
    Context(
      ..ctx("POST", "/private"),
      headers: dict.from_list([#("x-role", "partner")]),
    )
  ctx_h
  |> evaluate([
    any_of([
      method_in(["GET"]),
      header_one_of("x-role", ["internal", "partner"]),
    ]),
  ])
  |> should.equal(Allow)
}

pub fn not_rule_test() {
  ctx("DELETE", "/api")
  |> evaluate([not_(method_in(["GET", "POST"]))])
  |> should.equal(Allow)
}

pub fn not_with_claim_one_of_test() {
  let ctx_c =
    Context(..ctx("GET", "/api"), claims: dict.from_list([#("role", "admin")]))
  ctx_c
  |> evaluate([not_(claim_one_of("role", ["admin", "user"]))])
  |> should.equal(Deny("negated rule matched"))
}

pub fn evaluate_short_circuits_test() {
  ctx("DELETE", "/api")
  |> evaluate([method_in(["GET"]), path_prefix("/anything")])
  |> should.equal(Deny("method not allowed: DELETE"))
}

// claim_contains — multi-value comma-separated claim

pub fn claim_contains_single_value_allow_test() {
  let ctx_c =
    Context(..ctx("GET", "/api"), claims: dict.from_list([#("role", "admin")]))
  ctx_c
  |> evaluate([claim_contains("role", "admin")])
  |> should.equal(Allow)
}

pub fn claim_contains_multi_value_allow_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api"),
      claims: dict.from_list([#("role", "admin,user")]),
    )
  ctx_c
  |> evaluate([claim_contains("role", "user")])
  |> should.equal(Allow)
}

pub fn claim_contains_multi_value_allow_first_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api"),
      claims: dict.from_list([#("role", "admin,user,viewer")]),
    )
  ctx_c
  |> evaluate([claim_contains("role", "admin")])
  |> should.equal(Allow)
}

pub fn claim_contains_with_spaces_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api"),
      claims: dict.from_list([#("role", "admin, user")]),
    )
  ctx_c
  |> evaluate([claim_contains("role", "user")])
  |> should.equal(Allow)
}

pub fn claim_contains_deny_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api"),
      claims: dict.from_list([#("role", "viewer,guest")]),
    )
  ctx_c
  |> evaluate([claim_contains("role", "admin")])
  |> should.equal(Deny("claim does not contain: role=admin"))
}

pub fn claim_contains_missing_test() {
  ctx("GET", "/api")
  |> evaluate([claim_contains("role", "admin")])
  |> should.equal(Deny("missing required claim: role"))
}

// claim_contains_one_of

pub fn claim_contains_one_of_allow_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api"),
      claims: dict.from_list([#("role", "viewer,editor")]),
    )
  ctx_c
  |> evaluate([claim_contains_one_of("role", ["admin", "editor"])])
  |> should.equal(Allow)
}

pub fn claim_contains_one_of_deny_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api"),
      claims: dict.from_list([#("role", "viewer,guest")]),
    )
  ctx_c
  |> evaluate([claim_contains_one_of("role", ["admin", "user"])])
  |> should.equal(Deny("claim value mismatch: role"))
}

pub fn claim_contains_one_of_missing_test() {
  ctx("GET", "/api")
  |> evaluate([claim_contains_one_of("role", ["admin", "user"])])
  |> should.equal(Deny("missing required claim: role"))
}

// query_param

pub fn query_param_allow_test() {
  let ctx_q =
    Context(..ctx("GET", "/search"), query: dict.from_list([#("sort", "asc")]))
  ctx_q
  |> evaluate([query_param("sort", "asc")])
  |> should.equal(Allow)
}

pub fn query_param_deny_mismatch_test() {
  let ctx_q =
    Context(..ctx("GET", "/search"), query: dict.from_list([#("sort", "desc")]))
  ctx_q
  |> evaluate([query_param("sort", "asc")])
  |> should.equal(Deny("query param value mismatch: sort"))
}

pub fn query_param_deny_missing_test() {
  ctx("GET", "/search")
  |> evaluate([query_param("sort", "asc")])
  |> should.equal(Deny("missing required query param: sort"))
}

pub fn query_param_one_of_allow_test() {
  let ctx_q =
    Context(..ctx("GET", "/search"), query: dict.from_list([#("sort", "desc")]))
  ctx_q
  |> evaluate([query_param_one_of("sort", ["asc", "desc"])])
  |> should.equal(Allow)
}

pub fn query_param_one_of_deny_test() {
  let ctx_q =
    Context(
      ..ctx("GET", "/search"),
      query: dict.from_list([#("sort", "random")]),
    )
  ctx_q
  |> evaluate([query_param_one_of("sort", ["asc", "desc"])])
  |> should.equal(Deny("query param value mismatch: sort"))
}

// async_evaluate + to_async

pub fn async_evaluate_all_allow_test() {
  ctx("GET", "/api")
  |> async_evaluate([
    to_async(method_in(["GET"])),
    to_async(path_prefix("/api")),
  ])
  |> promise.map(fn(d) { d |> should.equal(Allow) })
}

pub fn async_evaluate_short_circuit_test() {
  ctx("POST", "/api")
  |> async_evaluate([
    to_async(method_in(["GET"])),
    to_async(path_prefix("/api")),
  ])
  |> promise.map(fn(d) { d |> should.equal(Deny("method not allowed: POST")) })
}

pub fn async_evaluate_empty_test() {
  ctx("GET", "/api")
  |> async_evaluate([])
  |> promise.map(fn(d) { d |> should.equal(Allow) })
}
