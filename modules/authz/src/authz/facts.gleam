import authz/policy.{type Context, type Decision, Allow, Deny}
import authz/security.{
  type SecurityFacts, NftsetDeny, SecurityFacts, WafDenied, WafDryRun,
}
import gleam/dict.{type Dict, fold, from_list, insert, merge, new}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}

/// Structured authz facts intended for downstream composition.
/// These stay as plain string-keyed values so other modules such as
/// response_templating can consume them through their own adapters.
pub fn decision(decision: Decision) -> Dict(String, String) {
  case decision {
    Allow ->
      from_list([
        #("status", "allow"),
        #("decision_code", "204"),
      ])
    Deny(status, reason) ->
      from_list([
        #("status", "deny"),
        #("decision_code", int.to_string(status)),
        #("reason", reason),
      ])
  }
}

pub fn query(ctx: Context) -> Dict(String, String) {
  prefix("query_", ctx.query)
}

pub fn session_subject(subject: Option(String)) -> Dict(String, String) {
  case subject {
    None -> new()
    Some(value) -> from_list([#("session_subject", value)])
  }
}

pub fn security(facts: SecurityFacts) -> Dict(String, String) {
  case facts {
    SecurityFacts(waf:, nftset:) -> {
      let waf_dict = case waf {
        None -> new()
        Some(security.WafFact(result:, rule_id:, score:, category:)) ->
          from_list([
            #("waf_result", case result {
              security.WafAllowed -> "allowed"
              WafDenied -> "denied"
              WafDryRun -> "dryrun"
            }),
            #("waf_rule_id", int.to_string(rule_id)),
            #("waf_score", int.to_string(score)),
            #("waf_category", category),
          ])
      }
      let nftset_dict = case nftset {
        None -> new()
        Some(security.NftsetFact(result:, matched_set:)) ->
          from_list([
            #("nftset_result", case result {
              security.NftsetAllow -> "allow"
              NftsetDeny -> "deny"
            }),
            #("nftset_matched_set", matched_set),
          ])
      }
      merge(waf_dict, nftset_dict)
    }
  }
}

pub fn compose(
  ctx: Context,
  decision decision_value: Decision,
  security security_facts: SecurityFacts,
  session_subject session_value: Option(String),
) -> Dict(String, String) {
  [
    decision(decision_value),
    query(ctx),
    session_subject(session_value),
    security(security_facts),
  ]
  |> list.fold(new(), merge)
}

fn prefix(p: String, values: Dict(String, String)) -> Dict(String, String) {
  fold(values, new(), fn(acc, key, value) { insert(acc, p <> key, value) })
}
