import gleeunit
import gleeunit/should
import workflow/pipeline.{Failed, Fetched, filter_ok, map_result}

pub fn main() {
  gleeunit.main()
}

pub fn fetched_variant_test() {
  Fetched(200, "ok") |> should.equal(Fetched(200, "ok"))
}

pub fn failed_variant_test() {
  Failed("timeout") |> should.equal(Failed("timeout"))
}

pub fn filter_ok_keeps_fetched_test() {
  let results = [Fetched(200, "a"), Failed("err"), Fetched(201, "b")]
  filter_ok(results) |> should.equal([#(200, "a"), #(201, "b")])
}

pub fn filter_ok_empty_test() {
  filter_ok([Failed("x"), Failed("y")]) |> should.equal([])
}

pub fn map_result_transforms_fetched_test() {
  let result = Fetched(200, "hello")
  map_result(result, fn(status, body) { Fetched(status, body <> "!") })
  |> should.equal(Fetched(200, "hello!"))
}

pub fn map_result_passes_through_failed_test() {
  let result = Failed("timeout")
  map_result(result, fn(_, _) { Fetched(200, "should not reach") })
  |> should.equal(Failed("timeout"))
}
