import gleam/dict.{type Dict}
import gleam/list
import njs/http.{type HTTPRequest}
import response_templating/model.{type Binding, Value}

/// Build bindings from a list of nginx request variable names.
/// Variables that are absent or empty are omitted, so `render_safe` is
/// the right render function when the variable set may be partial.
pub fn from_request(r: HTTPRequest, var_names: List(String)) -> List(Binding) {
  list.filter_map(var_names, fn(name) {
    case http.get_variable(r, name) {
      Ok(val) if val != "" -> Ok(Value(name:, value: val))
      _ -> Error(Nil)
    }
  })
}

/// Build bindings from a string-keyed dict (e.g., session claims, authz claims).
/// All entries in the dict become bindings; empty values are included.
pub fn from_dict(d: Dict(String, String)) -> List(Binding) {
  dict.to_list(d)
  |> list.map(fn(pair) {
    let #(name, value) = pair
    Value(name:, value:)
  })
}

/// Merge two binding lists. When the same name appears in both, the value
/// from `overrides` takes precedence.
pub fn merge(base: List(Binding), overrides: List(Binding)) -> List(Binding) {
  let base_dict =
    list.fold(base, dict.new(), fn(acc, b) {
      case b {
        Value(name:, value:) -> dict.insert(acc, name, value)
      }
    })
  let merged =
    list.fold(overrides, base_dict, fn(acc, b) {
      case b {
        Value(name:, value:) -> dict.insert(acc, name, value)
      }
    })
  dict.to_list(merged)
  |> list.map(fn(pair) { Value(name: pair.0, value: pair.1) })
}
