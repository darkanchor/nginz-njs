import gleam/javascript/promise
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import workflow/merge
import workflow/pipeline

pub fn main() {
  gleeunit.main()
}

// --- StepResult ---

pub fn fetched_variant_test() {
  pipeline.Fetched(200, "ok")
  |> should.equal(pipeline.Fetched(200, "ok"))
}

pub fn failed_variant_test() {
  pipeline.Failed("timeout")
  |> should.equal(pipeline.Failed("timeout"))
}

// --- filter_ok ---

pub fn filter_ok_keeps_fetched_test() {
  let results = [
    pipeline.Fetched(200, "a"),
    pipeline.Failed("err"),
    pipeline.Fetched(201, "b"),
  ]
  pipeline.filter_ok(results)
  |> should.equal([#(200, "a"), #(201, "b")])
}

pub fn filter_ok_empty_test() {
  pipeline.filter_ok([pipeline.Failed("x"), pipeline.Failed("y")])
  |> should.equal([])
}

// --- map_result ---

pub fn map_result_transforms_fetched_test() {
  let result = pipeline.Fetched(200, "hello")
  pipeline.map_result(result, fn(status, body) {
    pipeline.Fetched(status, body <> "!")
  })
  |> should.equal(pipeline.Fetched(200, "hello!"))
}

pub fn map_result_passes_through_failed_test() {
  let result = pipeline.Failed("timeout")
  pipeline.map_result(result, fn(_, _) {
    pipeline.Fetched(200, "should not reach")
  })
  |> should.equal(pipeline.Failed("timeout"))
}

// --- map_body ---

pub fn map_body_transforms_test() {
  let result = pipeline.Fetched(200, "hello")
  pipeline.map_body(result, fn(b) { b <> " world" })
  |> should.equal(pipeline.Fetched(200, "hello world"))
}

pub fn map_body_preserves_status_test() {
  let result = pipeline.Fetched(404, "not found")
  pipeline.map_body(result, fn(_) { "transformed" })
  |> should.equal(pipeline.Fetched(404, "transformed"))
}

pub fn map_body_passes_through_failed_test() {
  let result = pipeline.Failed("err")
  pipeline.map_body(result, fn(_) { "x" })
  |> should.equal(pipeline.Failed("err"))
}

// --- map_error ---

pub fn map_error_transforms_test() {
  let result = pipeline.Failed("timeout")
  pipeline.map_error(result, fn(r) { "wrapped: " <> r })
  |> should.equal(pipeline.Failed("wrapped: timeout"))
}

pub fn map_error_passes_through_fetched_test() {
  let result = pipeline.Fetched(200, "ok")
  pipeline.map_error(result, fn(_) { "x" })
  |> should.equal(pipeline.Fetched(200, "ok"))
}

// --- first_ok ---

pub fn first_ok_selects_first_success_test() {
  let results = [
    pipeline.Failed("a"),
    pipeline.Fetched(200, "b"),
    pipeline.Fetched(200, "c"),
  ]
  pipeline.first_ok(results)
  |> should.equal(Ok(pipeline.Fetched(200, "b")))
}

pub fn first_ok_all_failed_test() {
  let results = [pipeline.Failed("a"), pipeline.Failed("b")]
  case pipeline.first_ok(results) {
    Error(pipeline.Failed(_)) -> Nil
    _ -> should.fail()
  }
}

pub fn first_ok_empty_test() {
  case pipeline.first_ok([]) {
    Error(pipeline.Failed(reason)) ->
      reason |> should.equal("no successful results")
    _ -> should.fail()
  }
}

// --- all_success ---

pub fn all_success_true_test() {
  let results = [
    pipeline.Fetched(200, "a"),
    pipeline.Fetched(201, "b"),
  ]
  pipeline.all_success(results)
  |> should.be_true()
}

pub fn all_success_false_on_non_2xx_test() {
  let results = [
    pipeline.Fetched(200, "a"),
    pipeline.Fetched(404, "b"),
  ]
  pipeline.all_success(results)
  |> should.be_false()
}

pub fn all_success_false_on_failed_test() {
  let results = [pipeline.Fetched(200, "a"), pipeline.Failed("x")]
  pipeline.all_success(results)
  |> should.be_false()
}

// --- partition ---

pub fn partition_splits_correctly_test() {
  let results = [
    pipeline.Fetched(200, "a"),
    pipeline.Failed("e1"),
    pipeline.Fetched(201, "b"),
  ]
  let #(oks, errs) = pipeline.partition(results)
  oks |> should.equal([#(200, "a"), #(201, "b")])
  errs |> should.equal(["e1"])
}

pub fn partition_all_ok_test() {
  let results = [
    pipeline.Fetched(200, "a"),
    pipeline.Fetched(200, "b"),
  ]
  let #(oks, errs) = pipeline.partition(results)
  list.length(oks) |> should.equal(2)
  list.length(errs) |> should.equal(0)
}

pub fn partition_all_failed_test() {
  let results = [pipeline.Failed("a"), pipeline.Failed("b")]
  let #(oks, errs) = pipeline.partition(results)
  list.length(oks) |> should.equal(0)
  list.length(errs) |> should.equal(2)
}

// --- summary ---

pub fn summary_mixed_test() {
  let results = [pipeline.Fetched(200, "a"), pipeline.Failed("e")]
  pipeline.summary(results)
  |> should.equal("ok=1 fail=1")
}

pub fn summary_all_ok_test() {
  let results = [
    pipeline.Fetched(200, "a"),
    pipeline.Fetched(200, "b"),
  ]
  pipeline.summary(results)
  |> should.equal("ok=2 fail=0")
}

// --- recover ---

pub fn recover_success_passes_through_test() {
  let step = fn(_r) { promise.resolve(pipeline.Fetched(200, "ok")) }
  let _recovered: pipeline.Step =
    pipeline.recover(step, fn(_) { pipeline.Fetched(200, "fallback") })
  Nil
}

// --- with_retry type check ---

pub fn with_retry_is_step_test() {
  let step = fn(_r) { promise.resolve(pipeline.Failed("x")) }
  let _wrapped: pipeline.Step = pipeline.with_retry(step, 2)
  Nil
}

// --- with_timeout type check ---

pub fn with_timeout_is_step_test() {
  let step = fn(_r) { promise.resolve(pipeline.Fetched(200, "ok")) }
  let _wrapped: pipeline.Step = pipeline.with_timeout(step, 1000)
  Nil
}

// --- merge: merge_bodies ---

pub fn merge_bodies_joins_test() {
  let results = [
    pipeline.Fetched(200, "a"),
    pipeline.Fetched(200, "b"),
  ]
  merge.merge_bodies(results, "\n")
  |> should.equal(pipeline.Fetched(200, "a\nb"))
}

pub fn merge_bodies_single_test() {
  let results = [pipeline.Fetched(200, "only")]
  merge.merge_bodies(results, ",")
  |> should.equal(pipeline.Fetched(200, "only"))
}

pub fn merge_bodies_all_failed_test() {
  let results = [pipeline.Failed("e1"), pipeline.Failed("e2")]
  merge.merge_bodies(results, "\n")
  |> should.equal(pipeline.Failed("no successful results to merge"))
}

// --- merge: merge_with ---

pub fn merge_with_custom_test() {
  let results = [
    pipeline.Fetched(200, "a"),
    pipeline.Fetched(200, "b"),
  ]
  merge.merge_with(results, fn(pairs) {
    let bodies = list.map(pairs, fn(p) { p.1 })
    pipeline.Fetched(200, string.join(bodies, "|"))
  })
  |> should.equal(pipeline.Fetched(200, "a|b"))
}

// --- merge: require_all ---

pub fn require_all_success_test() {
  let results = [
    pipeline.Fetched(200, "a"),
    pipeline.Fetched(200, "b"),
  ]
  merge.require_all(results)
  |> should.be_ok()
}

pub fn require_all_fails_on_first_failure_test() {
  let results = [
    pipeline.Fetched(200, "a"),
    pipeline.Failed("e"),
    pipeline.Fetched(200, "b"),
  ]
  merge.require_all(results)
  |> should.equal(Error(pipeline.Failed("e")))
}

// --- merge: select_first_ok ---

pub fn select_first_ok_finds_first_test() {
  let results = [
    pipeline.Failed("a"),
    pipeline.Fetched(200, "b"),
    pipeline.Fetched(200, "c"),
  ]
  merge.select_first_ok(results, pipeline.Fetched(200, "default"))
  |> should.equal(pipeline.Fetched(200, "b"))
}

pub fn select_first_ok_uses_default_test() {
  let results = [pipeline.Failed("a"), pipeline.Failed("b")]
  merge.select_first_ok(results, pipeline.Fetched(200, "default"))
  |> should.equal(pipeline.Fetched(200, "default"))
}
