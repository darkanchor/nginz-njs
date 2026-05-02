import gleam/int
import gleam/list

pub type Template {
  Template(name: String, source: String, placeholders: List(String))
}

pub type Binding {
  Value(name: String, value: String)
}

pub fn demo_template() -> Template {
  Template(
    name: "demo",
    source: "Hello {{name}} — mode={{mode}}",
    placeholders: ["name", "mode"],
  )
}

pub fn summary(template: Template) -> String {
  case template {
    Template(name:, placeholders:, ..) ->
      name <> " placeholders=" <> int.to_string(list.length(placeholders))
  }
}
