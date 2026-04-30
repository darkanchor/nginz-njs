import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import response_transform/plan

fn describe(r: HTTPRequest) -> Nil {
  plan.demo_plan()
  |> plan.summary
  |> http.return_text(r, 200, _)
}

fn preview_plan(r: HTTPRequest) -> Nil {
  http.return_text(r, 200, "preview: " <> plan.summary(plan.demo_plan()))
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
  |> ngx.merge("preview_plan", preview_plan)
}
