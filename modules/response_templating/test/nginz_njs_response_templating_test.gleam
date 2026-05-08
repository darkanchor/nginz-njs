import gleeunit
import gleeunit/should
import response_templating/conditional
import response_templating/model
import response_templating/registry
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

pub fn conditional_select_returns_registered_template_test() {
  let fallback = model.demo_template()
  let reg =
    registry.new()
    |> registry.register(model.demo_json_template())

  conditional.select(reg, "demo_json", fallback)
  |> model.summary
  |> should.equal("demo_json kind=json placeholders=2")
}

pub fn conditional_render_if_chooses_branch_and_renders_safely_test() {
  let reg =
    registry.new()
    |> registry.register(model.new("allow", "allow {{name}}", ["name"]))
    |> registry.register(model.new("deny", "deny {{reason}}", ["reason"]))

  conditional.render_if(reg, False, "allow", "deny", [])
  |> should.equal("deny {{reason}}")
}

pub fn conditional_select_by_status_prefers_specific_then_default_then_fallback_test() {
  let fallback = model.new("fallback", "fallback", [])
  let reg =
    registry.new()
    |> registry.register(model.new("status_404", "specific", []))
    |> registry.register(model.new("status_default", "default", []))

  conditional.select_by_status(reg, "status", 404, fallback)
  |> model.summary
  |> should.equal("status_404 kind=text placeholders=0")

  conditional.select_by_status(reg, "status", 500, fallback)
  |> model.summary
  |> should.equal("status_default kind=text placeholders=0")

  conditional.select_by_status(registry.new(), "status", 500, fallback)
  |> model.summary
  |> should.equal("fallback kind=text placeholders=0")
}
