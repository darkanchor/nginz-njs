import gleam/dict
import gleam/list
import gleam/string
import response_templating/model.{type Binding, type Template, Template, Value}

pub fn binding(name: String, value: String) -> Binding {
  Value(name:, value:)
}

pub fn bindings_to_dict(bindings: List(Binding)) -> dict.Dict(String, String) {
  bindings
  |> list.map(fn(binding) {
    case binding {
      Value(name:, value:) -> #(name, value)
    }
  })
  |> dict.from_list
}

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
