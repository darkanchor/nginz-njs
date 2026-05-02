pub type Endpoint {
  Endpoint(name: String, path: String, method: String)
}

pub fn demo_endpoints() -> List(Endpoint) {
  [
    Endpoint(name: "describe", path: "/runtime/describe", method: "GET"),
    Endpoint(name: "health", path: "/runtime/health", method: "GET"),
    Endpoint(name: "inspect_flag", path: "/runtime/flag", method: "GET"),
    Endpoint(
      name: "toggle_flag_preview",
      path: "/runtime/flag/preview",
      method: "GET",
    ),
  ]
}

pub fn summary(endpoint: Endpoint) -> String {
  case endpoint {
    Endpoint(name:, path:, method:) -> method <> " " <> path <> " name=" <> name
  }
}
