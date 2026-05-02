import gleam/list
import gleam/string
import runtime_api/model

pub fn describe_routes() -> String {
  model.demo_endpoints()
  |> list.map(model.summary)
  |> string.join("\n")
}
