import gleam/dict.{type Dict}
import gleam/list
import njs/http.{type HTTPRequest}

/// Extract query parameters from nginx variables populated for each request.
/// For each name in `names`, reads `$arg_<name>` (set by nginx automatically)
/// and includes non-empty values in the returned dict.
pub fn from_request(
  r: HTTPRequest,
  names: List(String),
) -> Dict(String, String) {
  list.fold(names, dict.new(), fn(acc, name) {
    case http.get_variable(r, "arg_" <> name) {
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
