import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import response_templating/model
import response_templating/render

fn describe(r: HTTPRequest) -> Nil {
  model.demo_template()
  |> model.summary
  |> http.return_text(r, 200, _)
}

fn render_demo(r: HTTPRequest) -> Nil {
  model.demo_template()
  |> render.render([
    render.binding("name", "Kaiwu"),
    render.binding("mode", "demo"),
  ])
  |> http.return_text(r, 200, _)
}

fn render_from_request(r: HTTPRequest) -> Nil {
  let name = case http.get_variable(r, "arg_name") {
    Ok(value) -> value
    Error(_) -> "guest"
  }
  let mode = case http.get_variable(r, "arg_mode") {
    Ok(value) -> value
    Error(_) -> "standard"
  }

  model.demo_template()
  |> render.render([
    render.binding("name", name),
    render.binding("mode", mode),
  ])
  |> http.return_text(r, 200, _)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
  |> ngx.merge("render_demo", render_demo)
  |> ngx.merge("render_from_request", render_from_request)
}
