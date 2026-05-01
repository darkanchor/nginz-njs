import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import njs/buffer.{Utf8, from_string}
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import response_transform/eval
import response_transform/plan.{type Plan}

pub fn filter(
  plan: Plan,
  r: HTTPRequest,
  data: String,
  flags: JsObject,
) -> Nil {
  let out = case data {
    "" -> ""
    body -> apply_to_body(plan, body, -1)
  }
  let _ = http.send_buffer(r, from_string(out, Utf8), flags)
  Nil
}

pub fn filter_with_status(
  plan: Plan,
  status: Int,
  r: HTTPRequest,
  data: String,
  flags: JsObject,
) -> Nil {
  let out = case data {
    "" -> ""
    body -> apply_to_body(plan, body, status)
  }
  let _ = http.send_buffer(r, from_string(out, Utf8), flags)
  Nil
}

pub fn parse_object(body: String) -> Result(Dict(String, String), Nil) {
  case json.parse(body, decode.dict(decode.string, decode.string)) {
    Ok(d) -> Ok(d)
    Error(_) -> Error(Nil)
  }
}

pub fn encode_object(fields: Dict(String, String)) -> String {
  fields
  |> dict.to_list
  |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) })
  |> json.object
  |> json.to_string
}

fn apply_to_body(plan: Plan, body: String, status: Int) -> String {
  case parse_object(body) {
    Error(_) -> body
    Ok(fields) ->
      fields
      |> eval.apply_at_status(plan, status, _)
      |> encode_object
  }
}
