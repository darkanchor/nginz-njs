import gleam/dict.{type Dict}
import gleam/list
import njs/http.{type RequestForm, FormText}
import njs/ngx.{type JsObject}

/// Extract named fields from a parsed JSON body (readRequestJSON result).
/// Values are coerced to strings via ngx.to_string. Unknown or absent keys
/// are silently omitted from the returned dict.
pub fn from_json(obj: JsObject, keys: List(String)) -> Dict(String, String) {
  list.fold(keys, dict.new(), fn(acc, key) {
    case ngx.get(obj, key) {
      Ok(val) -> dict.insert(acc, key, ngx.to_string(val))
      Error(_) -> acc
    }
  })
}

/// Extract named fields from a parsed form body (readRequestForm result).
/// Only FormText values are included; file fields are silently skipped.
pub fn from_form(
  form: RequestForm,
  keys: List(String),
) -> Dict(String, String) {
  list.fold(keys, dict.new(), fn(acc, key) {
    case http.form_get(form, key) {
      Ok(FormText(value)) -> dict.insert(acc, key, value)
      _ -> acc
    }
  })
}
