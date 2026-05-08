import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import response_templating/model
import response_templating/registry
import response_templating/render
import response_templating/vars

fn describe(r: HTTPRequest) -> Nil {
  let reg =
    registry.new()
    |> registry.register(model.demo_template())
    |> registry.register(model.demo_json_template())
  registry.summary(reg)
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

fn render_safe_demo(r: HTTPRequest) -> Nil {
  model.demo_template()
  |> render.render_safe([render.binding("name", "Kaiwu")])
  |> http.return_text(r, 200, _)
}

fn render_from_request(r: HTTPRequest) -> Nil {
  let bindings = [
    render.binding("name", case http.get_variable(r, "arg_name") {
      Ok(v) -> v
      Error(_) -> "guest"
    }),
    render.binding("mode", case http.get_variable(r, "arg_mode") {
      Ok(v) -> v
      Error(_) -> "standard"
    }),
  ]
  model.demo_template()
  |> render.render(bindings)
  |> http.return_text(r, 200, _)
}

fn render_json_demo(r: HTTPRequest) -> Nil {
  let bindings = [
    render.binding("name", case http.get_variable(r, "arg_name") {
      Ok(v) -> v
      Error(_) -> "guest"
    }),
    render.binding("mode", case http.get_variable(r, "arg_mode") {
      Ok(v) -> v
      Error(_) -> "standard"
    }),
  ]
  let body =
    model.demo_json_template()
    |> render.render(bindings)
  let _ = http.set_headers_out(r, "Content-Type", "application/json")
  http.return_text(r, 200, body)
}

/// Render from nginx variables using the template's own placeholder list.
/// Missing variables keep the placeholder name as the value.
fn render_from_vars(r: HTTPRequest) -> Nil {
  let tmpl = model.demo_template()
  let bindings = vars.from_request(r, tmpl.placeholders)
  tmpl
  |> render.render_with_defaults(bindings)
  |> http.return_text(r, 200, _)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
  |> ngx.merge("render_demo", render_demo)
  |> ngx.merge("render_safe_demo", render_safe_demo)
  |> ngx.merge("render_from_request", render_from_request)
  |> ngx.merge("render_json_demo", render_json_demo)
  |> ngx.merge("render_from_vars", render_from_vars)
}
