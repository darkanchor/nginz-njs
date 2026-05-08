import gleam/int
import response_templating/model.{type Binding, type Template}
import response_templating/registry.{type Registry}
import response_templating/render

/// Look up a template by name, returning `fallback` if it is not registered.
pub fn select(
  registry: Registry,
  name: String,
  fallback: Template,
) -> Template {
  case registry.lookup(registry, name) {
    Ok(t) -> t
    Error(_) -> fallback
  }
}

/// Render one of two templates based on a boolean condition.
/// Returns an HTML comment if the chosen template name is not in the registry.
pub fn render_if(
  registry: Registry,
  condition: Bool,
  on_true: String,
  on_false: String,
  bindings: List(Binding),
) -> String {
  let name = case condition {
    True -> on_true
    False -> on_false
  }
  case registry.lookup(registry, name) {
    Ok(template) -> render.render_safe(template, bindings)
    Error(_) -> "<!-- template not found: " <> name <> " -->"
  }
}

/// Select a template by HTTP status code.
/// Looks up `<prefix>_<status>` first, then `<prefix>_default`, then `fallback`.
pub fn select_by_status(
  registry: Registry,
  prefix: String,
  status: Int,
  fallback: Template,
) -> Template {
  let key = prefix <> "_" <> int.to_string(status)
  case registry.lookup(registry, key) {
    Ok(t) -> t
    Error(_) ->
      case registry.lookup(registry, prefix <> "_default") {
        Ok(t) -> t
        Error(_) -> fallback
      }
  }
}
