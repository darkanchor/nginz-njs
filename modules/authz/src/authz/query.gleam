import gleam/dict.{type Dict}
import gleam/list
import njs/ngx.{type JsObject}

/// Extract query parameters from nginx variables populated for each request.
/// For each name in `names`, reads `$arg_<name>` (set by nginx automatically)
/// and includes non-empty values in the returned dict.
pub fn from_vars(vars: JsObject, names: List(String)) -> Dict(String, String) {
  list.fold(names, dict.new(), fn(acc, name) {
    case ngx.get(vars, "arg_" <> name) {
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
