import control_api/model
import control_api/response
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn endpoints_count_test() {
  model.endpoints()
  |> list.length
  |> should.equal(6)
}

pub fn json_ok_test() {
  response.json_ok([#("flag", "test")])
  |> should.equal("{\"status\":\"ok\",\"flag\":\"test\"}")
}

pub fn json_error_test() {
  response.json_error("not found")
  |> should.equal("{\"status\":\"error\",\"message\":\"not found\"}")
}

pub fn route_description_contains_health_test() {
  let routes = model.describe_all()
  routes
  |> string.contains("GET /runtime/health")
  |> should.be_true
}

pub fn route_description_contains_flag_test() {
  let routes = model.describe_all()
  routes
  |> string.contains("/runtime/flag")
  |> should.be_true
}
