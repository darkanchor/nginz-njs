import gleam/int
import gleam/list

/// Output kind: determines Content-Type and rendering format.
pub type TemplateKind {
  TextTemplate
  JsonTemplate
}

pub type Template {
  Template(
    name: String,
    source: String,
    placeholders: List(String),
    kind: TemplateKind,
  )
}

pub type Binding {
  Value(name: String, value: String)
}

pub type TemplateError {
  UnknownPlaceholder(name: String)
  EmptySource
}

pub fn new(
  name: String,
  source: String,
  placeholders: List(String),
) -> Template {
  Template(name:, source:, placeholders:, kind: TextTemplate)
}

pub fn json(
  name: String,
  source: String,
  placeholders: List(String),
) -> Template {
  Template(name:, source:, placeholders:, kind: JsonTemplate)
}

pub fn validate(template: Template) -> Result(Template, TemplateError) {
  case template.source {
    "" -> Error(EmptySource)
    _ -> Ok(template)
  }
}

pub fn demo_template() -> Template {
  Template(
    name: "demo",
    source: "Hello {{name}} — mode={{mode}}",
    placeholders: ["name", "mode"],
    kind: TextTemplate,
  )
}

pub fn demo_json_template() -> Template {
  Template(
    name: "demo_json",
    source: "{\"greeting\":\"Hello {{name}}\",\"mode\":\"{{mode}}\"}",
    placeholders: ["name", "mode"],
    kind: JsonTemplate,
  )
}

pub fn summary(template: Template) -> String {
  let kind_str = case template.kind {
    TextTemplate -> "text"
    JsonTemplate -> "json"
  }
  case template {
    Template(name:, placeholders:, ..) ->
      name
      <> " kind="
      <> kind_str
      <> " placeholders="
      <> int.to_string(list.length(placeholders))
  }
}
