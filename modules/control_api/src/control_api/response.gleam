import gleam/list
import gleam/string

/// Build a JSON object string from a flat list of string key-value pairs.
/// Values are JSON-string-escaped. Suitable for simple operational responses
/// where all values are strings or string-encoded numbers.
pub fn json_object(fields: List(#(String, String))) -> String {
  let pairs =
    list.map(fields, fn(pair) {
      let #(k, v) = pair
      "\"" <> json_escape(k) <> "\":\"" <> json_escape(v) <> "\""
    })
  "{" <> string.join(pairs, ",") <> "}"
}

/// Build a JSON ok response: {"status":"ok", ...extra_fields}.
pub fn json_ok(extra: List(#(String, String))) -> String {
  json_object([#("status", "ok"), ..extra])
}

/// Build a JSON error response: {"status":"error","message":"<msg>"}.
pub fn json_error(message: String) -> String {
  json_object([#("status", "error"), #("message", message)])
}

/// Escape a string value for embedding in a JSON string literal.
/// Handles the minimum set required by the JSON spec.
fn json_escape(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\t", "\\t")
}
