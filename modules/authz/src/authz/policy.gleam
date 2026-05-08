import gleam/dict.{type Dict}
import gleam/int
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/string

pub type Decision {
  Allow
  Deny(status: Int, reason: String)
}

pub type Context {
  Context(
    method: String,
    path: String,
    remote_addr: String,
    headers: Dict(String, String),
    claims: Dict(String, String),
    query: Dict(String, String),
  )
}

pub type Rule =
  fn(Context) -> Decision

/// An async rule for effectful checks (remote auth, introspection).
/// Compose with `async_evaluate`; lift a sync Rule with `to_async`.
pub type AsyncRule =
  fn(Context) -> Promise(Decision)

pub fn evaluate(ctx: Context, rules: List(Rule)) -> Decision {
  list.fold_until(rules, Allow, fn(_, rule) {
    case rule(ctx) {
      Allow -> list.Continue(Allow)
      Deny(s, r) -> list.Stop(Deny(s, r))
    }
  })
}

/// Evaluate a list of async rules in sequence, short-circuiting on the
/// first Deny. Sync rules can be lifted with `to_async`.
pub fn async_evaluate(
  ctx: Context,
  rules: List(AsyncRule),
) -> Promise(Decision) {
  list.fold(rules, promise.resolve(Allow), fn(acc, rule) {
    use prev <- promise.await(acc)
    case prev {
      Deny(_, _) -> promise.resolve(prev)
      Allow -> rule(ctx)
    }
  })
}

/// Lift a sync Rule into an AsyncRule.
pub fn to_async(rule: Rule) -> AsyncRule {
  fn(ctx: Context) -> Promise(Decision) { promise.resolve(rule(ctx)) }
}

/// Convenience constructor — Deny with 401 Unauthorized.
pub fn deny_401(reason: String) -> Decision {
  Deny(401, reason)
}

/// Convenience constructor — Deny with 403 Forbidden.
pub fn deny_403(reason: String) -> Decision {
  Deny(403, reason)
}

pub fn method_in(allowed: List(String)) -> Rule {
  fn(ctx: Context) -> Decision {
    case list.contains(allowed, ctx.method) {
      True -> Allow
      False -> Deny(403, "method not allowed: " <> ctx.method)
    }
  }
}

pub fn path_prefix(prefix: String) -> Rule {
  fn(ctx: Context) -> Decision {
    case string.starts_with(ctx.path, prefix) {
      True -> Allow
      False -> Deny(403, "path not allowed: " <> ctx.path)
    }
  }
}

pub fn require_header(name: String, value: String) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.headers, name) {
      Ok(v) if v == value -> Allow
      Ok(_) -> Deny(403, "header value mismatch: " <> name)
      Error(_) -> Deny(403, "missing required header: " <> name)
    }
  }
}

pub fn header_one_of(name: String, allowed: List(String)) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.headers, name) {
      Ok(v) ->
        case list.contains(allowed, v) {
          True -> Allow
          False -> Deny(403, "header value mismatch: " <> name)
        }
      Error(_) -> Deny(403, "missing required header: " <> name)
    }
  }
}

pub fn has_claim(key: String, value: String) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.claims, key) {
      Ok(v) if v == value -> Allow
      Ok(_) -> Deny(403, "claim value mismatch: " <> key)
      Error(_) -> Deny(403, "missing required claim: " <> key)
    }
  }
}

pub fn claim_one_of(key: String, allowed: List(String)) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.claims, key) {
      Ok(v) ->
        case list.contains(allowed, v) {
          True -> Allow
          False -> Deny(403, "claim value mismatch: " <> key)
        }
      Error(_) -> Deny(403, "missing required claim: " <> key)
    }
  }
}

pub fn all_of(rules: List(Rule)) -> Rule {
  fn(ctx: Context) -> Decision { evaluate(ctx, rules) }
}

pub fn any_of(rules: List(Rule)) -> Rule {
  fn(ctx: Context) -> Decision {
    list.fold_until(rules, Deny(403, "no rule matched"), fn(_, rule) {
      case rule(ctx) {
        Allow -> list.Stop(Allow)
        Deny(_, _) -> list.Continue(Deny(403, "no rule matched"))
      }
    })
  }
}

pub fn not_(rule: Rule) -> Rule {
  fn(ctx: Context) -> Decision {
    case rule(ctx) {
      Allow -> Deny(403, "negated rule matched")
      Deny(_, _) -> Allow
    }
  }
}

fn split_multi(value: String) -> List(String) {
  value
  |> string.split(",")
  |> list.map(string.trim)
  |> list.filter(fn(s) { s != "" })
}

/// Allow if a comma-separated claim value contains `value` as one segment.
pub fn claim_contains(key: String, value: String) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.claims, key) {
      Ok(v) ->
        case list.contains(split_multi(v), value) {
          True -> Allow
          False -> Deny(403, "claim does not contain: " <> key <> "=" <> value)
        }
      Error(_) -> Deny(403, "missing required claim: " <> key)
    }
  }
}

/// Allow if a comma-separated claim value contains any element from `allowed`.
pub fn claim_contains_one_of(key: String, allowed: List(String)) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.claims, key) {
      Ok(v) ->
        case list.any(split_multi(v), fn(s) { list.contains(allowed, s) }) {
          True -> Allow
          False -> Deny(403, "claim value mismatch: " <> key)
        }
      Error(_) -> Deny(403, "missing required claim: " <> key)
    }
  }
}

/// Allow if the claim key exists with any non-empty value.
/// Useful for OIDC identity gates where the subject must be present but the
/// exact value is not known at policy-write time.
pub fn claim_present(key: String) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.claims, key) {
      Ok(_) -> Allow
      Error(_) -> Deny(401, "missing required claim: " <> key)
    }
  }
}

pub fn query_param(key: String, value: String) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.query, key) {
      Ok(v) if v == value -> Allow
      Ok(_) -> Deny(403, "query param value mismatch: " <> key)
      Error(_) -> Deny(403, "missing required query param: " <> key)
    }
  }
}

pub fn query_param_one_of(key: String, allowed: List(String)) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.query, key) {
      Ok(v) ->
        case list.contains(allowed, v) {
          True -> Allow
          False -> Deny(403, "query param value mismatch: " <> key)
        }
      Error(_) -> Deny(403, "missing required query param: " <> key)
    }
  }
}

/// Allow if the request's remote address falls within any of the given CIDR
/// ranges. Accepts plain IPv4 addresses (treated as /32) or `a.b.c.d/prefix`
/// notation. Fails closed (Deny) for non-IPv4 addresses or invalid CIDRs.
pub fn remote_addr_in(cidrs: List(String)) -> Rule {
  fn(ctx: Context) -> Decision {
    case parse_ip4(ctx.remote_addr) {
      Error(_) -> Deny(403, "remote addr not IPv4: " <> ctx.remote_addr)
      Ok(addr) ->
        case list.any(cidrs, fn(cidr) { addr_in_cidr(addr, cidr) }) {
          True -> Allow
          False -> Deny(403, "remote addr not allowed: " <> ctx.remote_addr)
        }
    }
  }
}

fn addr_in_cidr(addr: Int, cidr: String) -> Bool {
  case parse_cidr(cidr) {
    Error(_) -> False
    Ok(#(subnet, prefix)) -> {
      let mask = case prefix {
        0 -> 0
        p -> int.bitwise_shift_left(-1, 32 - p)
      }
      int.bitwise_and(addr, mask) == int.bitwise_and(subnet, mask)
    }
  }
}

fn parse_ip4(ip: String) -> Result(Int, Nil) {
  case string.split(ip, ".") {
    [a_str, b_str, c_str, d_str] ->
      case
        int.parse(a_str),
        int.parse(b_str),
        int.parse(c_str),
        int.parse(d_str)
      {
        Ok(a), Ok(b), Ok(c), Ok(d) ->
          case
            a >= 0
            && a <= 255
            && b >= 0
            && b <= 255
            && c >= 0
            && c <= 255
            && d >= 0
            && d <= 255
          {
            True -> Ok(a * 16_777_216 + b * 65_536 + c * 256 + d)
            False -> Error(Nil)
          }
        _, _, _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
}

fn parse_cidr(cidr: String) -> Result(#(Int, Int), Nil) {
  case string.split_once(cidr, "/") {
    Ok(#(ip_str, prefix_str)) ->
      case parse_ip4(ip_str), int.parse(prefix_str) {
        Ok(ip), Ok(prefix) ->
          case prefix >= 0 && prefix <= 32 {
            True -> Ok(#(ip, prefix))
            False -> Error(Nil)
          }
        _, _ -> Error(Nil)
      }
    Error(_) ->
      case parse_ip4(cidr) {
        Ok(ip) -> Ok(#(ip, 32))
        Error(_) -> Error(Nil)
      }
  }
}
