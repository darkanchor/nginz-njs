import control_api/model
import gleam/list
import gleam/string

pub fn describe_routes() -> String {
  model.demo_endpoints()
  |> list.map(model.summary)
  |> string.join("\n")
}
