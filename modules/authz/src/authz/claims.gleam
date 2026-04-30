import gleam/dict.{type Dict}
import gleam/list
import njs/ngx.{type JsObject}

/// Extract JWT claims from nginx variables populated by the native jwt module.
/// For each name in `names`, reads `jwt_claim_<name>` and includes non-empty
/// values in the returned dict keyed by claim name.
pub fn from_vars(vars: JsObject, names: List(String)) -> Dict(String, String) {
  list.fold(names, dict.new(), fn(acc, name) {
    case ngx.get(vars, "jwt_claim_" <> name) {
      Ok(v) -> {
        let val = ngx.to_string(v)
        case val {
          "" -> acc
          _ -> dict.insert(acc, name, val)
        }
      }
      Error(_) -> acc
    }
  })
}
