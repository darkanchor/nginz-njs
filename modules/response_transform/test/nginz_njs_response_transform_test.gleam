import gleam/dict
import gleeunit
import gleeunit/should
import response_transform/body
import response_transform/eval
import response_transform/plan.{
  ConflictingOperations, DropField, EmptyPlan, MaskField, Plan, RenameField,
  SetField, WhenStatus,
}

pub fn main() {
  gleeunit.main()
}

pub fn demo_plan_summary_test() {
  plan.demo_plan()
  |> plan.summary
  |> should.equal(
    "default_response_transform [mask:user.email, drop:internal.trace, rename:user.id->user_id]",
  )
}

pub fn demo_plan_name_is_stable_test() {
  let plan.Plan(name:, operations: _) = plan.demo_plan()
  name |> should.equal("default_response_transform")
}

// plan: new operation summaries

pub fn summary_set_field_test() {
  Plan(name: "p", operations: [SetField("env", "prod")])
  |> plan.summary
  |> should.equal("p [set:env=prod]")
}

pub fn summary_when_status_test() {
  Plan(name: "p", operations: [WhenStatus(404, DropField("data"))])
  |> plan.summary
  |> should.equal("p [when(404):drop:data]")
}

// plan: validate

pub fn validate_demo_plan_test() {
  plan.demo_plan() |> plan.validate |> should.be_ok
}

pub fn validate_empty_plan_test() {
  Plan(name: "empty", operations: [])
  |> plan.validate
  |> should.equal(Error(EmptyPlan))
}

pub fn validate_conflicting_ops_test() {
  Plan(name: "p", operations: [MaskField("email"), DropField("email")])
  |> plan.validate
  |> should.equal(Error(ConflictingOperations("email")))
}

pub fn validate_when_status_not_conflict_test() {
  Plan(name: "p", operations: [
    WhenStatus(404, DropField("data")),
    WhenStatus(200, MaskField("data")),
  ])
  |> plan.validate
  |> should.be_ok
}

// plan: compose

pub fn compose_two_plans_test() {
  let a = Plan(name: "a", operations: [MaskField("x")])
  let b = Plan(name: "b", operations: [DropField("y")])
  let composed = plan.compose([a, b])
  composed.name |> should.equal("a")
  composed.operations
  |> should.equal([MaskField("x"), DropField("y")])
}

pub fn compose_empty_test() {
  plan.compose([]).name |> should.equal("empty")
}

// eval: apply

pub fn eval_mask_field_test() {
  let fields = dict.from_list([#("email", "secret"), #("name", "Alice")])
  eval.apply(Plan(name: "p", operations: [MaskField("email")]), fields)
  |> should.equal(dict.from_list([#("email", "***"), #("name", "Alice")]))
}

pub fn eval_mask_missing_field_test() {
  let fields = dict.from_list([#("name", "Alice")])
  eval.apply(Plan(name: "p", operations: [MaskField("email")]), fields)
  |> should.equal(dict.from_list([#("name", "Alice")]))
}

pub fn eval_drop_field_test() {
  let fields = dict.from_list([#("trace", "abc"), #("name", "Bob")])
  eval.apply(Plan(name: "p", operations: [DropField("trace")]), fields)
  |> should.equal(dict.from_list([#("name", "Bob")]))
}

pub fn eval_rename_field_test() {
  let fields = dict.from_list([#("user_id", "42"), #("name", "Carol")])
  eval.apply(
    Plan(name: "p", operations: [RenameField("user_id", "userId")]),
    fields,
  )
  |> should.equal(dict.from_list([#("userId", "42"), #("name", "Carol")]))
}

pub fn eval_set_field_test() {
  let fields = dict.from_list([#("env", "old")])
  eval.apply(Plan(name: "p", operations: [SetField("env", "prod")]), fields)
  |> should.equal(dict.from_list([#("env", "prod")]))
}

pub fn eval_when_status_match_test() {
  let fields = dict.from_list([#("data", "value"), #("other", "keep")])
  eval.apply_at_status(
    Plan(name: "p", operations: [WhenStatus(404, DropField("data"))]),
    404,
    fields,
  )
  |> should.equal(dict.from_list([#("other", "keep")]))
}

pub fn eval_when_status_no_match_test() {
  let fields = dict.from_list([#("data", "value"), #("other", "keep")])
  eval.apply_at_status(
    Plan(name: "p", operations: [WhenStatus(404, DropField("data"))]),
    200,
    fields,
  )
  |> should.equal(fields)
}

// body: parse and encode

pub fn body_parse_object_test() {
  body.parse_object("{\"name\":\"Alice\",\"role\":\"admin\"}")
  |> should.equal(Ok(dict.from_list([#("name", "Alice"), #("role", "admin")])))
}

pub fn body_parse_object_invalid_test() {
  body.parse_object("not json")
  |> should.equal(Error(Nil))
}

pub fn body_parse_object_non_string_values_test() {
  body.parse_object("{\"count\":42}")
  |> should.equal(Error(Nil))
}

pub fn body_encode_object_round_trip_test() {
  let fields = dict.from_list([#("a", "1"), #("b", "2")])
  let encoded = body.encode_object(fields)
  body.parse_object(encoded)
  |> should.equal(Ok(fields))
}
