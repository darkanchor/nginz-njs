import gleam/dict.{type Dict}
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
  )
}

pub type Rule =
  fn(Context) -> Decision

pub fn evaluate(ctx: Context, rules: List(Rule)) -> Decision {
  list.fold_until(rules, Allow, fn(_, rule) {
    case rule(ctx) {
      Allow -> list.Continue(Allow)
      Deny(r) -> list.Stop(Deny(r))
    }
  })
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

pub fn has_claim(key: String, value: String) -> Rule {
  fn(ctx: Context) -> Decision {
    case dict.get(ctx.claims, key) {
      Ok(v) if v == value -> Allow
      Ok(_) -> Deny("claim value mismatch: " <> key)
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
