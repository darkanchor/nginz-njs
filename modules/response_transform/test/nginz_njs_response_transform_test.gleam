import gleeunit
import gleeunit/should
import response_transform/plan

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
