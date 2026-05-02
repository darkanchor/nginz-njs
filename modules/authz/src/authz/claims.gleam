import gleam/dict.{type Dict}
import gleam/list
import njs/http.{type HTTPRequest}

/// Extract JWT claims from nginx variables populated by the native jwt module.
/// For each name in `names`, reads `jwt_claim_<name>` and includes non-empty
/// values in the returned dict keyed by claim name.
pub fn from_request(
  r: HTTPRequest,
  names: List(String),
) -> Dict(String, String) {
  list.fold(names, dict.new(), fn(acc, name) {
    case http.get_variable(r, "jwt_claim_" <> name) {
      Ok(val) -> {
        case val {
          "" -> acc
          _ -> dict.insert(acc, name, val)
        }
      }
      Error(_) -> acc
    }
  })
}
