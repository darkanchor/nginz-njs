import authz/policy.{type Context, type Decision, Allow, Deny}
import authz/security.{
  type NftsetFact, type WafFact, NftsetDeny, WafDenied, WafDryRun,
}
import gleam/dict
import gleam/int
import gleam/option.{type Option, None, Some}
import gleam/string
import njs/http.{type HTTPRequest}

/// Set the `X-Authz-Status` response header to `allow` or `deny`.
/// The upstream proxy can forward this header to the backend service.
pub fn inject_status(r: HTTPRequest, decision: Decision) -> HTTPRequest {
  let status = case decision {
    Allow -> "allow"
    Deny(_, _) -> "deny"
  }
  http.set_headers_out(r, "X-Authz-Status", status)
}

/// Set `X-Authz-<Claim>` response headers for every entry in `ctx.claims`.
/// Claim names are title-cased, e.g. `role` → `X-Authz-Role`.
pub fn inject_claims(r: HTTPRequest, ctx: Context) -> HTTPRequest {
  dict.fold(ctx.claims, r, fn(r, key, value) {
    http.set_headers_out(r, "X-Authz-" <> title_case(key), value)
  })
}

/// Inject WAF facts as response headers for downstream observation.
/// Sets X-Authz-Waf-Result, X-Authz-Waf-Score, X-Authz-Waf-Category,
/// X-Authz-Waf-Rule-Id. Safe to call in dry-run mode — does not deny.
/// Useful with auth_request so downstream locations can audit WAF signals
/// without being blocked by the WAF deny path.
pub fn inject_waf_facts(r: HTTPRequest, fact: Option(WafFact)) -> HTTPRequest {
  case fact {
    None -> r
    Some(security.WafFact(result:, rule_id:, score:, category:)) -> {
      let result_str = case result {
        security.WafAllowed -> "allowed"
        WafDenied -> "denied"
        WafDryRun -> "dryrun"
      }
      r
      |> http.set_headers_out("X-Authz-Waf-Result", result_str)
      |> http.set_headers_out("X-Authz-Waf-Score", int.to_string(score))
      |> http.set_headers_out("X-Authz-Waf-Category", category)
      |> http.set_headers_out("X-Authz-Waf-Rule-Id", int.to_string(rule_id))
    }
  }
}

/// Inject nftset facts as response headers.
/// Sets X-Authz-Nftset-Result and X-Authz-Nftset-Matched-Set.
pub fn inject_nftset_facts(
  r: HTTPRequest,
  fact: Option(NftsetFact),
) -> HTTPRequest {
  case fact {
    None -> r
    Some(security.NftsetFact(result:, matched_set:)) -> {
      let result_str = case result {
        NftsetDeny -> "deny"
        security.NftsetAllow -> "allow"
      }
      r
      |> http.set_headers_out("X-Authz-Nftset-Result", result_str)
      |> http.set_headers_out("X-Authz-Nftset-Matched-Set", matched_set)
    }
  }
}

fn title_case(s: String) -> String {
  case string.split(s, "") {
    [] -> ""
    [first, ..rest] -> string.uppercase(first) <> string.join(rest, "")
  }
}
