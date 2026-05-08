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
  |> should.equal("demo kind=text placeholders=2")
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

pub fn render_safe_preserves_missing_placeholder_test() {
  model.demo_template()
  |> render.render_safe([render.binding("name", "Alice")])
  |> should.equal("Hello Alice — mode={{mode}}")
}

pub fn render_with_defaults_uses_name_for_missing_test() {
  model.demo_template()
  |> render.render_with_defaults([render.binding("name", "Alice")])
  |> should.equal("Hello Alice — mode=mode")
}

pub fn json_template_kind_test() {
  model.demo_json_template().kind
  |> should.equal(model.JsonTemplate)
}
