import gleeunit
import gleeunit/should
import response_templating/model
import response_templating/render

pub fn main() {
  gleeunit.main()
}

pub fn demo_template_summary_test() {
  model.demo_template()
  |> model.summary
  |> should.equal("demo placeholders=2")
}

pub fn render_replaces_known_placeholders_test() {
  model.demo_template()
  |> render.render([
    render.binding("name", "Alice"),
    render.binding("mode", "preview"),
  ])
  |> should.equal("Hello Alice — mode=preview")
}

pub fn render_missing_placeholder_defaults_empty_test() {
  model.demo_template()
  |> render.render([render.binding("name", "Alice")])
  |> should.equal("Hello Alice — mode=")
}
