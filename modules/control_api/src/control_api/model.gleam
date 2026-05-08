import gleam/list
import gleam/string

pub type Endpoint {
  Endpoint(name: String, path: String, method: String, description: String)
}

pub fn endpoints() -> List(Endpoint) {
  [
    Endpoint(
      name: "describe",
      path: "/runtime/describe",
      method: "GET",
      description: "List all control API endpoints",
    ),
    Endpoint(
      name: "health",
      path: "/runtime/health",
      method: "GET",
      description: "Module health check",
    ),
    Endpoint(
      name: "system_info",
      path: "/runtime/system",
      method: "GET",
      description: "Runtime system info (timestamp, version)",
    ),
    Endpoint(
      name: "inspect_flag",
      path: "/runtime/flag",
      method: "GET",
      description: "Inspect a feature flag by ?name=<flag>",
    ),
    Endpoint(
      name: "toggle_flag",
      path: "/runtime/flag",
      method: "POST",
      description: "Set a feature flag: ?name=<flag>&enabled=<1|0>&pct=<0-100>",
    ),
    Endpoint(
      name: "probe_cache",
      path: "/runtime/cache/probe",
      method: "GET",
      description: "Probe a shared dict by ?dict=<name>",
    ),
  ]
}

pub fn summary(endpoint: Endpoint) -> String {
  endpoint.method <> " " <> endpoint.path <> " — " <> endpoint.description
}

pub fn describe_all() -> String {
  endpoints()
  |> list.map(summary)
  |> string.join("\n")
}
