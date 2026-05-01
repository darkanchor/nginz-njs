import gleam/int
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import response_transform/body
import response_transform/plan

fn describe(r: HTTPRequest) -> Nil {
  plan.demo_plan()
  |> plan.summary
  |> http.return_text(r, 200, _)
}

fn preview_plan(r: HTTPRequest) -> Nil {
  http.return_text(r, 200, "preview: " <> plan.summary(plan.demo_plan()))
}

fn clear_content_length(r: HTTPRequest) -> Nil {
  let _ = http.set_headers_out(r, "content-length", "")
  Nil
}

fn transform(r: HTTPRequest, data: String, flags: JsObject) -> Nil {
  body.filter(plan.demo_plan(), r, data, flags)
}

fn transform_with_status(r: HTTPRequest, data: String, flags: JsObject) -> Nil {
  let vars = http.get_variables(r)
  let status = case ngx.get(vars, "status") {
    Ok(v) ->
      case int.parse(ngx.to_string(v)) {
        Ok(n) -> n
        Error(_) -> -1
      }
    Error(_) -> -1
  }
  body.filter_with_status(plan.demo_plan(), status, r, data, flags)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
  |> ngx.merge("preview_plan", preview_plan)
  |> ngx.merge("clear_content_length", clear_content_length)
  |> ngx.merge("transform", transform)
  |> ngx.merge("transform_with_status", transform_with_status)
}
