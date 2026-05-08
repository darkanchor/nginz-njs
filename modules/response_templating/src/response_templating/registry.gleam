import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import response_templating/model.{type Template}

/// A named registry of templates. Looked up by template name at render time.
pub type Registry {
  Registry(templates: Dict(String, Template))
}

pub fn new() -> Registry {
  Registry(templates: dict.new())
}

/// Register a template under its `name` field.
pub fn register(registry: Registry, template: Template) -> Registry {
  Registry(templates: dict.insert(registry.templates, template.name, template))
}

/// Look up a template by name.
pub fn lookup(registry: Registry, name: String) -> Result(Template, Nil) {
  dict.get(registry.templates, name)
}

/// List the names of all registered templates.
pub fn names(registry: Registry) -> List(String) {
  dict.keys(registry.templates)
}

/// Build a summary listing the number of registered templates.
pub fn summary(registry: Registry) -> String {
  "registry count=" <> int.to_string(list.length(names(registry)))
}
