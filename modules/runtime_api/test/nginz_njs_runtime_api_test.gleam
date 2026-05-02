import gleam/list
import gleeunit
import gleeunit/should
import runtime_api/model
import runtime_api/response
import runtime_api/router

pub fn main() {
  gleeunit.main()
}

pub fn demo_endpoints_count_test() {
  model.demo_endpoints()
  |> list.length
  |> should.equal(4)
}

pub fn response_ok_test() {
  response.ok("runtime_api=ready")
  |> should.equal("ok runtime_api=ready")
}

pub fn route_description_contains_health_test() {
  router.describe_routes()
  |> should.equal(
    "GET /runtime/describe name=describe\nGET /runtime/health name=health\nGET /runtime/flag name=inspect_flag\nGET /runtime/flag/preview name=toggle_flag_preview",
  )
}
