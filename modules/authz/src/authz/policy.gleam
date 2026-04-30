import gleam/dict.{type Dict}
import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/string

pub type Decision {
  Allow
  Deny(reason: String)
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
      Deny(r) -> list.Stop(Deny(r))
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
      Deny(_) -> promise.resolve(prev)
      Allow -> rule(ctx)
    }
  })
}

/// Lift a sync Rule into an AsyncRule.
pub fn to_async(rule: Rule) -> AsyncRule {
  fn(ctx: Context) -> Promise(Decision) { promise.resolve(rule(ctx)) }
}

pub fn method_in(allowed: List(String)) -> Rule {
  fn(ctx: Context) -> Decision {
    case list.contains(allowed, ctx.method) {
      True -> Allow
      False -> Deny("method not allowed: " <> ctx.method)
    }
  }
}

pub fn path_prefix(prefix: String) -> Rule {
  fn(ctx: Context) -> Decision {
    case string.starts_with(ctx.path, prefix) {
      True -> Allow
      False -> Deny("path not allowed: " <> ctx.path)
    }
  }
}

pub fn require_header(name: String, value: String) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.headers, name) {
      Ok(v) if v == value -> Allow
      Ok(_) -> Deny("header value mismatch: " <> name)
      Error(_) -> Deny("missing required header: " <> name)
    }
  }
}

pub fn header_one_of(name: String, allowed: List(String)) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.headers, name) {
      Ok(v) ->
        case list.contains(allowed, v) {
          True -> Allow
          False -> Deny("header value mismatch: " <> name)
        }
      Error(_) -> Deny("missing required header: " <> name)
    }
  }
}

pub fn has_claim(key: String, value: String) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.claims, key) {
      Ok(v) if v == value -> Allow
      Ok(_) -> Deny("claim value mismatch: " <> key)
      Error(_) -> Deny("missing required claim: " <> key)
    }
  }
}

pub fn claim_one_of(key: String, allowed: List(String)) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.claims, key) {
      Ok(v) ->
        case list.contains(allowed, v) {
          True -> Allow
          False -> Deny("claim value mismatch: " <> key)
        }
      Error(_) -> Deny("missing required claim: " <> key)
    }
  }
}

pub fn all_of(rules: List(Rule)) -> Rule {
  fn(ctx: Context) -> Decision { evaluate(ctx, rules) }
}

pub fn any_of(rules: List(Rule)) -> Rule {
  fn(ctx: Context) -> Decision {
    list.fold_until(rules, Deny("no rule matched"), fn(_, rule) {
      case rule(ctx) {
        Allow -> list.Stop(Allow)
        Deny(_) -> list.Continue(Deny("no rule matched"))
      }
    })
  }
}

pub fn not_(rule: Rule) -> Rule {
  fn(ctx: Context) -> Decision {
    case rule(ctx) {
      Allow -> Deny("negated rule matched")
      Deny(_) -> Allow
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
          False -> Deny("claim does not contain: " <> key <> "=" <> value)
        }
      Error(_) -> Deny("missing required claim: " <> key)
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
          False -> Deny("claim value mismatch: " <> key)
        }
      Error(_) -> Deny("missing required claim: " <> key)
    }
  }
}

pub fn query_param(key: String, value: String) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.query, key) {
      Ok(v) if v == value -> Allow
      Ok(_) -> Deny("query param value mismatch: " <> key)
      Error(_) -> Deny("missing required query param: " <> key)
    }
  }
}

pub fn query_param_one_of(key: String, allowed: List(String)) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.query, key) {
      Ok(v) ->
        case list.contains(allowed, v) {
          True -> Allow
          False -> Deny("query param value mismatch: " <> key)
        }
      Error(_) -> Deny("missing required query param: " <> key)
    }
  }
}
