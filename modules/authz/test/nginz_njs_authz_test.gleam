import authz/facts
import authz/metrics
import authz/policy.{
  type Context, Allow, Context, Deny, all_of, any_of, async_evaluate, body_param,
  body_param_one_of, body_param_present, claim_contains, claim_contains_one_of,
  claim_one_of, claim_present, deny_401, deny_403, evaluate, has_claim,
  header_one_of, method_in, not_, path_prefix, query_param, query_param_one_of,
  remote_addr_in, require_header, to_async,
}
import authz/security.{
  NftsetAllow, NftsetDeny, NftsetFact, SecurityFacts, WafAllowed, WafDenied,
  WafDryRun, WafFact, nftset_pass, pass, waf_pass,
}
import gleam/dict
import gleam/javascript/promise
import gleam/option.{None, Some}
import gleeunit
import gleeunit/should
import metrics/line

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
    body: dict.new(),
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
  |> should.equal(Deny(403, "method not allowed: DELETE"))
}

pub fn path_prefix_allow_test() {
  ctx("GET", "/api/users")
  |> evaluate([path_prefix("/api")])
  |> should.equal(Allow)
}

pub fn path_prefix_deny_test() {
  ctx("GET", "/admin/secret")
  |> evaluate([path_prefix("/api")])
  |> should.equal(Deny(403, "path not allowed: /admin/secret"))
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
  |> should.equal(Deny(403, "missing required header: x-api-key"))
}

pub fn require_header_deny_mismatch_test() {
  let ctx_h =
    Context(
      ..ctx("GET", "/api"),
      headers: dict.from_list([#("x-api-key", "wrong")]),
    )
  ctx_h
  |> evaluate([require_header("x-api-key", "secret")])
  |> should.equal(Deny(403, "header value mismatch: x-api-key"))
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
  |> should.equal(Deny(403, "missing required claim: role"))
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
  |> should.equal(Deny(403, "missing required claim: role"))
}

pub fn claim_one_of_deny_mismatch_test() {
  let ctx_c =
    Context(..ctx("GET", "/api"), claims: dict.from_list([#("role", "guest")]))
  ctx_c
  |> evaluate([claim_one_of("role", ["admin", "user"])])
  |> should.equal(Deny(403, "claim value mismatch: role"))
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
  |> should.equal(Deny(403, "missing required header: x-role"))
}

pub fn header_one_of_deny_mismatch_test() {
  let ctx_h =
    Context(
      ..ctx("GET", "/api"),
      headers: dict.from_list([#("x-role", "external")]),
    )
  ctx_h
  |> evaluate([header_one_of("x-role", ["internal", "partner"])])
  |> should.equal(Deny(403, "header value mismatch: x-role"))
}

pub fn all_of_allow_test() {
  ctx("GET", "/api/users")
  |> evaluate([all_of([method_in(["GET"]), path_prefix("/api")])])
  |> should.equal(Allow)
}

pub fn all_of_deny_first_test() {
  ctx("POST", "/api/users")
  |> evaluate([all_of([method_in(["GET"]), path_prefix("/api")])])
  |> should.equal(Deny(403, "method not allowed: POST"))
}

pub fn all_of_deny_second_test() {
  ctx("GET", "/admin/panel")
  |> evaluate([all_of([method_in(["GET"]), path_prefix("/api")])])
  |> should.equal(Deny(403, "path not allowed: /admin/panel"))
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
  |> should.equal(Deny(403, "no rule matched"))
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
  |> should.equal(Deny(403, "negated rule matched"))
}

pub fn evaluate_short_circuits_test() {
  ctx("DELETE", "/api")
  |> evaluate([method_in(["GET"]), path_prefix("/anything")])
  |> should.equal(Deny(403, "method not allowed: DELETE"))
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
  |> should.equal(Deny(403, "claim does not contain: role=admin"))
}

pub fn claim_contains_missing_test() {
  ctx("GET", "/api")
  |> evaluate([claim_contains("role", "admin")])
  |> should.equal(Deny(403, "missing required claim: role"))
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
  |> should.equal(Deny(403, "claim value mismatch: role"))
}

pub fn claim_contains_one_of_missing_test() {
  ctx("GET", "/api")
  |> evaluate([claim_contains_one_of("role", ["admin", "user"])])
  |> should.equal(Deny(403, "missing required claim: role"))
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
  |> should.equal(Deny(403, "query param value mismatch: sort"))
}

pub fn query_param_deny_missing_test() {
  ctx("GET", "/search")
  |> evaluate([query_param("sort", "asc")])
  |> should.equal(Deny(403, "missing required query param: sort"))
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
  |> should.equal(Deny(403, "query param value mismatch: sort"))
}

pub fn composed_policy_allow_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api/portal"),
      claims: dict.from_list([
        #("sub", "user-123"),
        #("email", "user@example.com"),
        #("role", "ops,support"),
      ]),
      query: dict.from_list([#("view", "summary")]),
    )
  ctx_c
  |> evaluate([
    all_of([
      method_in(["GET"]),
      claim_present("sub"),
      claim_present("email"),
      claim_contains_one_of("role", ["admin", "support"]),
      query_param_one_of("view", ["summary", "full"]),
    ]),
  ])
  |> should.equal(Allow)
}

pub fn composed_policy_missing_identity_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api/portal"),
      claims: dict.from_list([
        #("role", "admin"),
        #("email", "user@example.com"),
      ]),
      query: dict.from_list([#("view", "summary")]),
    )
  ctx_c
  |> evaluate([
    all_of([
      method_in(["GET"]),
      claim_present("sub"),
      claim_present("email"),
      claim_contains_one_of("role", ["admin", "support"]),
      query_param_one_of("view", ["summary", "full"]),
    ]),
  ])
  |> should.equal(Deny(401, "missing required claim: sub"))
}

pub fn composed_policy_query_mismatch_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api/portal"),
      claims: dict.from_list([
        #("sub", "user-123"),
        #("email", "user@example.com"),
        #("role", "admin"),
      ]),
      query: dict.from_list([#("view", "detail")]),
    )
  ctx_c
  |> evaluate([
    all_of([
      method_in(["GET"]),
      claim_present("sub"),
      claim_present("email"),
      claim_contains_one_of("role", ["admin", "support"]),
      query_param_one_of("view", ["summary", "full"]),
    ]),
  ])
  |> should.equal(Deny(403, "query param value mismatch: view"))
}

// deny_401 / deny_403 helpers

pub fn deny_401_test() {
  deny_401("missing credentials")
  |> should.equal(Deny(401, "missing credentials"))
}

pub fn deny_403_test() {
  deny_403("insufficient scope")
  |> should.equal(Deny(403, "insufficient scope"))
}

pub fn deny_status_propagates_test() {
  let rule: policy.Rule = fn(_ctx) { deny_401("no bearer token") }
  ctx("GET", "/api")
  |> evaluate([rule])
  |> should.equal(Deny(401, "no bearer token"))
}

// remote_addr_in — IPv4 CIDR allowlist

pub fn remote_addr_in_exact_allow_test() {
  Context(..ctx("GET", "/api"), remote_addr: "192.168.1.5")
  |> evaluate([remote_addr_in(["192.168.1.5"])])
  |> should.equal(Allow)
}

pub fn remote_addr_in_cidr_allow_test() {
  Context(..ctx("GET", "/api"), remote_addr: "10.0.0.42")
  |> evaluate([remote_addr_in(["10.0.0.0/8"])])
  |> should.equal(Allow)
}

pub fn remote_addr_in_cidr_24_allow_test() {
  Context(..ctx("GET", "/api"), remote_addr: "192.168.1.200")
  |> evaluate([remote_addr_in(["192.168.1.0/24"])])
  |> should.equal(Allow)
}

pub fn remote_addr_in_multiple_cidrs_allow_test() {
  Context(..ctx("GET", "/api"), remote_addr: "172.16.5.1")
  |> evaluate([remote_addr_in(["10.0.0.0/8", "172.16.0.0/12"])])
  |> should.equal(Allow)
}

pub fn remote_addr_in_deny_test() {
  Context(..ctx("GET", "/api"), remote_addr: "8.8.8.8")
  |> evaluate([remote_addr_in(["192.168.0.0/16", "10.0.0.0/8"])])
  |> should.equal(Deny(403, "remote addr not allowed: 8.8.8.8"))
}

pub fn remote_addr_in_loopback_test() {
  ctx("GET", "/api")
  |> evaluate([remote_addr_in(["127.0.0.0/8"])])
  |> should.equal(Allow)
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
  |> promise.map(fn(d) {
    d |> should.equal(Deny(403, "method not allowed: POST"))
  })
}

pub fn async_evaluate_empty_test() {
  ctx("GET", "/api")
  |> async_evaluate([])
  |> promise.map(fn(d) { d |> should.equal(Allow) })
}

// --- Metrics adapter ---

pub fn metrics_allow_counter_test() {
  let m = metrics.allow_counter("api_gateway")
  line.render_statsd(m)
  |> should.equal(
    "nginz.authz_decision_total:1|c|#result:allow,route:api_gateway",
  )
}

pub fn metrics_deny_counter_test() {
  let m = metrics.deny_counter("admin_panel", 403, "missing claim: role")
  line.render_statsd(m)
  |> should.equal(
    "nginz.authz_decision_total:1|c|#result:deny,route:admin_panel,status:403,reason:missing claim: role",
  )
}

pub fn metrics_deny_counter_truncates_long_reason_test() {
  let long =
    "this is a very long reason string that exceeds the 64 character limit for tag values in statsd"
  let m = metrics.deny_counter("admin_panel", 401, long)
  line.render_statsd(m)
  |> should.equal(
    "nginz.authz_decision_total:1|c|#result:deny,route:admin_panel,status:401,reason:this is a very long reason string that exceeds the 64 character ",
  )
}

pub fn metrics_decision_allow_test() {
  let m = metrics.decision(Allow, "api_gateway")
  line.render_statsd(m)
  |> should.equal(
    "nginz.authz_decision_total:1|c|#result:allow,route:api_gateway",
  )
}

pub fn metrics_decision_deny_test() {
  let m = metrics.decision(Deny(403, "path not allowed"), "api_gateway")
  line.render_statsd(m)
  |> should.equal(
    "nginz.authz_decision_total:1|c|#result:deny,route:api_gateway,status:403,reason:path not allowed",
  )
}

pub fn metrics_opa_call_outcome_allow_test() {
  let #(outcome, timing) = metrics.opa_call_outcome(Allow, "opa", 15)
  line.render_statsd(outcome)
  |> should.equal("nginz.authz_opa_call_total:1|c|#result:allow,route:opa")
  line.render_statsd(timing)
  |> should.equal("nginz.authz_opa_latency_ms:15|ms|#route:opa")
}

pub fn metrics_opa_call_outcome_deny_test() {
  let #(outcome, timing) =
    metrics.opa_call_outcome(Deny(403, "policy decision"), "opa", 25)
  line.render_statsd(outcome)
  |> should.equal(
    "nginz.authz_opa_call_total:1|c|#result:deny,route:opa,status:403,reason:policy decision",
  )
  line.render_statsd(timing)
  |> should.equal("nginz.authz_opa_latency_ms:25|ms|#route:opa")
}

// --- claim_present ---

pub fn claim_present_allow_test() {
  let ctx_c =
    Context(..ctx("GET", "/api"), claims: dict.from_list([#("sub", "u123")]))
  ctx_c
  |> evaluate([claim_present("sub")])
  |> should.equal(Allow)
}

pub fn claim_present_deny_missing_test() {
  ctx("GET", "/api")
  |> evaluate([claim_present("sub")])
  |> should.equal(Deny(401, "missing required claim: sub"))
}

// --- security: waf_pass ---

pub fn waf_pass_none_test() {
  waf_pass(None)
  |> should.equal(Allow)
}

pub fn waf_pass_allowed_test() {
  waf_pass(
    Some(WafFact(result: WafAllowed, rule_id: 0, score: 0, category: "")),
  )
  |> should.equal(Allow)
}

pub fn waf_pass_dryrun_test() {
  waf_pass(
    Some(WafFact(result: WafDryRun, rule_id: 42, score: 30, category: "sqli")),
  )
  |> should.equal(Allow)
}

pub fn waf_pass_denied_with_category_test() {
  waf_pass(
    Some(WafFact(result: WafDenied, rule_id: 10, score: 80, category: "sqli")),
  )
  |> should.equal(Deny(403, "waf: request denied [sqli]"))
}

pub fn waf_pass_denied_no_category_test() {
  waf_pass(Some(WafFact(result: WafDenied, rule_id: 0, score: 0, category: "")))
  |> should.equal(Deny(403, "waf: request denied"))
}

pub fn composed_policy_waf_denied_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api/portal"),
      claims: dict.from_list([
        #("sub", "user-123"),
        #("email", "user@example.com"),
        #("role", "support"),
      ]),
      query: dict.from_list([#("view", "full")]),
    )
  let decision =
    evaluate(ctx_c, [
      all_of([
        method_in(["GET"]),
        claim_present("sub"),
        claim_present("email"),
        claim_contains_one_of("role", ["admin", "support"]),
        query_param_one_of("view", ["summary", "full"]),
        fn(_ctx) {
          waf_pass(
            Some(WafFact(
              result: WafDenied,
              rule_id: 10,
              score: 90,
              category: "sqli",
            )),
          )
        },
      ]),
    ])
  decision |> should.equal(Deny(403, "waf: request denied [sqli]"))
}

// --- security: nftset_pass ---

pub fn nftset_pass_none_test() {
  nftset_pass(None)
  |> should.equal(Allow)
}

pub fn nftset_pass_allow_test() {
  nftset_pass(Some(NftsetFact(result: NftsetAllow, matched_set: "")))
  |> should.equal(Allow)
}

pub fn nftset_pass_deny_with_set_name_test() {
  nftset_pass(Some(NftsetFact(result: NftsetDeny, matched_set: "blocklist")))
  |> should.equal(Deny(403, "nftset: denied by blocklist"))
}

pub fn nftset_pass_deny_no_set_name_test() {
  nftset_pass(Some(NftsetFact(result: NftsetDeny, matched_set: "")))
  |> should.equal(Deny(403, "nftset: request denied"))
}

pub fn composed_policy_nftset_denied_test() {
  let ctx_c =
    Context(
      ..ctx("GET", "/api/portal"),
      claims: dict.from_list([
        #("sub", "user-123"),
        #("email", "user@example.com"),
        #("role", "support"),
      ]),
      query: dict.from_list([#("view", "full")]),
    )
  let decision =
    evaluate(ctx_c, [
      all_of([
        method_in(["GET"]),
        claim_present("sub"),
        claim_present("email"),
        claim_contains_one_of("role", ["admin", "support"]),
        query_param_one_of("view", ["summary", "full"]),
        fn(_ctx) {
          nftset_pass(
            Some(NftsetFact(result: NftsetDeny, matched_set: "blocklist")),
          )
        },
      ]),
    ])
  decision |> should.equal(Deny(403, "nftset: denied by blocklist"))
}

// body_param — access-phase body field rules

pub fn body_param_allow_test() {
  let ctx_b =
    Context(..ctx("POST", "/api"), body: dict.from_list([#("action", "read")]))
  ctx_b
  |> evaluate([body_param("action", "read")])
  |> should.equal(Allow)
}

pub fn body_param_deny_mismatch_test() {
  let ctx_b =
    Context(..ctx("POST", "/api"), body: dict.from_list([#("action", "write")]))
  ctx_b
  |> evaluate([body_param("action", "read")])
  |> should.equal(Deny(403, "body param value mismatch: action"))
}

pub fn body_param_deny_missing_test() {
  ctx("POST", "/api")
  |> evaluate([body_param("action", "read")])
  |> should.equal(Deny(403, "missing required body param: action"))
}

pub fn body_param_one_of_allow_test() {
  let ctx_b =
    Context(..ctx("POST", "/api"), body: dict.from_list([#("action", "write")]))
  ctx_b
  |> evaluate([body_param_one_of("action", ["read", "write"])])
  |> should.equal(Allow)
}

pub fn body_param_one_of_deny_test() {
  let ctx_b =
    Context(
      ..ctx("POST", "/api"),
      body: dict.from_list([#("action", "delete")]),
    )
  ctx_b
  |> evaluate([body_param_one_of("action", ["read", "write"])])
  |> should.equal(Deny(403, "body param value mismatch: action"))
}

pub fn body_param_present_allow_test() {
  let ctx_b =
    Context(..ctx("POST", "/api"), body: dict.from_list([#("user_id", "u42")]))
  ctx_b
  |> evaluate([body_param_present("user_id")])
  |> should.equal(Allow)
}

pub fn body_param_present_deny_test() {
  ctx("POST", "/api")
  |> evaluate([body_param_present("user_id")])
  |> should.equal(Deny(401, "missing required body param: user_id"))
}

pub fn body_param_composed_with_method_test() {
  let ctx_b =
    Context(
      ..ctx("POST", "/api"),
      body: dict.from_list([#("action", "read"), #("resource", "orders")]),
    )
  ctx_b
  |> evaluate([
    all_of([
      method_in(["POST"]),
      body_param_one_of("action", ["read", "list"]),
      body_param_present("resource"),
    ]),
  ])
  |> should.equal(Allow)
}

pub fn security_pass_waf_deny_wins_test() {
  pass(SecurityFacts(
    waf: Some(WafFact(result: WafDenied, rule_id: 7, score: 90, category: "xss")),
    nftset: Some(NftsetFact(result: NftsetDeny, matched_set: "blocklist")),
  ))
  |> should.equal(Deny(403, "waf: request denied [xss]"))
}

pub fn security_pass_nftset_runs_after_waf_allow_test() {
  pass(SecurityFacts(
    waf: Some(WafFact(result: WafDryRun, rule_id: 7, score: 90, category: "xss")),
    nftset: Some(NftsetFact(result: NftsetDeny, matched_set: "blocklist")),
  ))
  |> should.equal(Deny(403, "nftset: denied by blocklist"))
}

pub fn facts_compose_includes_structured_fields_test() {
  let ctx_f =
    Context(..ctx("GET", "/api"), query: dict.from_list([#("view", "summary")]))
  let fact_map =
    facts.compose(
      ctx_f,
      Deny(401, "missing required claim: session_subject"),
      SecurityFacts(
        waf: Some(WafFact(
          result: WafDryRun,
          rule_id: 42,
          score: 70,
          category: "sqli",
        )),
        nftset: Some(NftsetFact(result: NftsetAllow, matched_set: "")),
      ),
      Some("alice"),
    )
  dict.get(fact_map, "status") |> should.equal(Ok("deny"))
  dict.get(fact_map, "decision_code") |> should.equal(Ok("401"))
  dict.get(fact_map, "reason")
  |> should.equal(Ok("missing required claim: session_subject"))
  dict.get(fact_map, "query_view") |> should.equal(Ok("summary"))
  dict.get(fact_map, "session_subject") |> should.equal(Ok("alice"))
  dict.get(fact_map, "waf_result") |> should.equal(Ok("dryrun"))
  dict.get(fact_map, "nftset_result") |> should.equal(Ok("allow"))
}
