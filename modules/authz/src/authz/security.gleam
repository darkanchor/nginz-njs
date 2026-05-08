import authz/policy.{type Context, type Decision, type Rule, Allow, Deny}
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/result
import njs/http.{type HTTPRequest}

pub type WafResult {
  WafAllowed
  WafDenied
  WafDryRun
}

/// Facts read from $waf_result, $waf_rule_id, $waf_score, $waf_category.
pub type WafFact {
  WafFact(result: WafResult, rule_id: Int, score: Int, category: String)
}

pub type NftsetResult {
  NftsetAllow
  NftsetDeny
}

/// Facts read from $nftset_result and $nftset_matched_set.
pub type NftsetFact {
  NftsetFact(result: NftsetResult, matched_set: String)
}

fn read_int_var(r: HTTPRequest, name: String) -> Int {
  case http.get_variable(r, name) {
    Ok(s) -> result.unwrap(int.parse(s), 0)
    Error(_) -> 0
  }
}

fn read_str_var(r: HTTPRequest, name: String) -> String {
  case http.get_variable(r, name) {
    Ok(s) -> s
    Error(_) -> ""
  }
}

/// Parse WAF facts from nginx variables set by the native waf module.
/// Returns None when $waf_result is absent (waf module not active or not matched).
pub fn waf_from_request(r: HTTPRequest) -> Option(WafFact) {
  case http.get_variable(r, "waf_result") {
    Error(_) -> None
    Ok("") -> None
    Ok(s) -> {
      let waf_result = case s {
        "denied" -> WafDenied
        "dryrun" -> WafDryRun
        _ -> WafAllowed
      }
      Some(WafFact(
        result: waf_result,
        rule_id: read_int_var(r, "waf_rule_id"),
        score: read_int_var(r, "waf_score"),
        category: read_str_var(r, "waf_category"),
      ))
    }
  }
}

/// Parse nftset facts from nginx variables set by the native nftset module.
/// Returns None when $nftset_result is absent (nftset module not active or no match).
pub fn nftset_from_request(r: HTTPRequest) -> Option(NftsetFact) {
  case http.get_variable(r, "nftset_result") {
    Error(_) -> None
    Ok("") -> None
    Ok(s) -> {
      let nftset_result = case s {
        "deny" -> NftsetDeny
        _ -> NftsetAllow
      }
      Some(NftsetFact(
        result: nftset_result,
        matched_set: read_str_var(r, "nftset_matched_set"),
      ))
    }
  }
}

/// Allow-path WAF check: pass if the WAF result is allowed or dry-run.
/// Dry-run allows the request through for observation only.
/// Does not reconstruct deny decisions from error_page or access-phase context.
pub fn waf_pass(fact: Option(WafFact)) -> Decision {
  case fact {
    None -> Allow
    Some(WafFact(result: WafAllowed, ..)) -> Allow
    Some(WafFact(result: WafDryRun, ..)) -> Allow
    Some(WafFact(result: WafDenied, category: "", ..)) ->
      Deny(403, "waf: request denied")
    Some(WafFact(result: WafDenied, category: cat, ..)) ->
      Deny(403, "waf: request denied [" <> cat <> "]")
  }
}

/// Allow-path nftset check: pass if the nftset result is "allow" or not set.
pub fn nftset_pass(fact: Option(NftsetFact)) -> Decision {
  case fact {
    None -> Allow
    Some(NftsetFact(result: NftsetAllow, ..)) -> Allow
    Some(NftsetFact(result: NftsetDeny, matched_set: "")) ->
      Deny(403, "nftset: request denied")
    Some(NftsetFact(result: NftsetDeny, matched_set: ms)) ->
      Deny(403, "nftset: denied by " <> ms)
  }
}

/// Rule factory: reads WAF facts from the request and applies the allow-path check.
/// Compose into all_of / any_of policy trees alongside claim and path rules.
pub fn waf_pass_rule(r: HTTPRequest) -> Rule {
  fn(_ctx: Context) -> Decision { waf_pass(waf_from_request(r)) }
}

/// Rule factory: reads nftset facts from the request and applies the allow-path check.
pub fn nftset_pass_rule(r: HTTPRequest) -> Rule {
  fn(_ctx: Context) -> Decision { nftset_pass(nftset_from_request(r)) }
}
