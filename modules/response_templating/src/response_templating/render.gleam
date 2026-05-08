import gleam/dict
import gleam/list
import gleam/string
import response_templating/model.{type Binding, type Template, Template, Value}

pub fn binding(name: String, value: String) -> Binding {
  Value(name:, value:)
}

pub fn bindings_to_dict(bindings: List(Binding)) -> dict.Dict(String, String) {
  bindings
  |> list.map(fn(b) {
    case b {
      Value(name:, value:) -> #(name, value)
    }
  })
  |> dict.from_list
}

/// Render a template, substituting each placeholder with its binding value.
/// Missing bindings are replaced with "".
pub fn render(template: Template, bindings: List(Binding)) -> String {
  let values = bindings_to_dict(bindings)
  case template {
    Template(source:, placeholders:, ..) ->
      list.fold(placeholders, source, fn(rendered, placeholder) {
        let replacement = case dict.get(values, placeholder) {
          Ok(value) -> value
          Error(_) -> ""
        }
        string.replace(rendered, "{{" <> placeholder <> "}}", replacement)
      })
  }
}

/// Like `render` but missing bindings keep the original `{{placeholder}}`
/// text rather than becoming empty strings. Useful during development to
/// spot unbound variables in the output.
pub fn render_safe(template: Template, bindings: List(Binding)) -> String {
  let values = bindings_to_dict(bindings)
  case template {
    Template(source:, placeholders:, ..) ->
      list.fold(placeholders, source, fn(rendered, placeholder) {
        let replacement = case dict.get(values, placeholder) {
          Ok(value) -> value
          Error(_) -> "{{" <> placeholder <> "}}"
        }
        string.replace(rendered, "{{" <> placeholder <> "}}", replacement)
      })
  }
}

/// Like `render` but missing bindings default to the placeholder name itself.
/// Produces readable output when the binding set is partial.
pub fn render_with_defaults(
  template: Template,
  bindings: List(Binding),
) -> String {
  let values = bindings_to_dict(bindings)
  case template {
    Template(source:, placeholders:, ..) ->
      list.fold(placeholders, source, fn(rendered, placeholder) {
        let replacement = case dict.get(values, placeholder) {
          Ok(value) -> value
          Error(_) -> placeholder
        }
        string.replace(rendered, "{{" <> placeholder <> "}}", replacement)
      })
  }
}
