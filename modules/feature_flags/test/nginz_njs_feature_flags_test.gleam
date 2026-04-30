import feature_flags/evaluation.{
  ByRemoteAddr, ByRequestId, ByUserId, Flag, bucket, is_enabled,
}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn disabled_flag_always_off_test() {
  let flag = Flag(name: "dark_mode", enabled: False, rollout_pct: 100)
  is_enabled(flag, ByRequestId("any-id"))
  |> should.equal(False)
}

pub fn full_rollout_always_on_test() {
  let flag = Flag(name: "dark_mode", enabled: True, rollout_pct: 100)
  is_enabled(flag, ByRequestId("any-id"))
  |> should.equal(True)
}

pub fn zero_rollout_always_off_test() {
  let flag = Flag(name: "dark_mode", enabled: True, rollout_pct: 0)
  is_enabled(flag, ByRequestId("any-id"))
  |> should.equal(False)
}

pub fn bucket_is_deterministic_test() {
  let b1 = bucket(ByRequestId("user-123"))
  let b2 = bucket(ByRequestId("user-123"))
  b1 |> should.equal(b2)
}

pub fn bucket_is_in_range_test() {
  let b = bucket(ByRemoteAddr("192.168.1.1"))
  { b >= 0 && b < 100 } |> should.equal(True)
}

pub fn bucket_differs_by_key_type_test() {
  let id = "same-value"
  let b_req = bucket(ByRequestId(id))
  let b_user = bucket(ByUserId(id))
  let b_addr = bucket(ByRemoteAddr(id))
  b_req |> should.equal(b_user)
  b_req |> should.equal(b_addr)
}

pub fn rollout_boundary_test() {
  let b = bucket(ByRequestId("test-id"))
  let at_boundary = Flag(name: "f", enabled: True, rollout_pct: b)
  let one_over = Flag(name: "f", enabled: True, rollout_pct: b + 1)
  is_enabled(at_boundary, ByRequestId("test-id")) |> should.equal(False)
  is_enabled(one_over, ByRequestId("test-id")) |> should.equal(True)
}
