import feature_flags/evaluation.{
  ByRemoteAddr, ByRequestId, ByUserId, Flag, ForceOff, ForceOn, NoOverride,
  Variant, VariantConfig, VariantFlag, bucket, describe_boolean,
  describe_variant, evaluate, is_enabled, parse_enabled, parse_override,
  parse_rollout_pct, parse_variant_configs, select_variant,
}
import gleam/string
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

pub fn bucket_same_key_type_is_stable_test() {
  let id = "same-value"
  let b_req = bucket(ByRequestId(id))
  let b_user = bucket(ByUserId(id))
  let b_addr = bucket(ByRemoteAddr(id))
  { b_req == b_user } |> should.equal(False)
  { b_req == b_addr } |> should.equal(False)
  { b_user == b_addr } |> should.equal(False)
}

pub fn rollout_boundary_test() {
  let b = bucket(ByRequestId("test-id"))
  let at_boundary = Flag(name: "f", enabled: True, rollout_pct: b)
  let one_over = Flag(name: "f", enabled: True, rollout_pct: b + 1)
  is_enabled(at_boundary, ByRequestId("test-id")) |> should.equal(False)
  is_enabled(one_over, ByRequestId("test-id")) |> should.equal(True)
}

// --- Override tests ---

pub fn force_on_overrides_disabled_flag_test() {
  let flag = Flag(name: "f", enabled: False, rollout_pct: 0)
  evaluate(flag, ByRequestId("any"), ForceOn)
  |> should.equal(True)
}

pub fn force_on_overrides_zero_rollout_test() {
  let flag = Flag(name: "f", enabled: True, rollout_pct: 0)
  evaluate(flag, ByRequestId("any"), ForceOn)
  |> should.equal(True)
}

pub fn force_off_overrides_enabled_flag_test() {
  let flag = Flag(name: "f", enabled: True, rollout_pct: 100)
  evaluate(flag, ByRequestId("any"), ForceOff)
  |> should.equal(False)
}

pub fn no_override_falls_through_test() {
  let flag = Flag(name: "f", enabled: True, rollout_pct: 100)
  evaluate(flag, ByRequestId("any"), NoOverride)
  |> should.equal(True)
}

pub fn no_override_falls_through_disabled_test() {
  let flag = Flag(name: "f", enabled: False, rollout_pct: 100)
  evaluate(flag, ByRequestId("any"), NoOverride)
  |> should.equal(False)
}

// --- Override precedence: override wins over rollout ---

pub fn force_off_beats_rollout_test() {
  let b = bucket(ByRequestId("u"))
  let flag = Flag(name: "f", enabled: True, rollout_pct: b + 1)
  // Without override the flag would be on (bucket < rollout_pct).
  is_enabled(flag, ByRequestId("u")) |> should.equal(True)
  // ForceOff must defeat the rollout.
  evaluate(flag, ByRequestId("u"), ForceOff) |> should.equal(False)
}

pub fn force_on_beats_rollout_test() {
  let b = bucket(ByRequestId("u"))
  let flag = Flag(name: "f", enabled: True, rollout_pct: b)
  // Without override the flag would be off (bucket >= rollout_pct).
  is_enabled(flag, ByRequestId("u")) |> should.equal(False)
  // ForceOn must defeat the rollout.
  evaluate(flag, ByRequestId("u"), ForceOn) |> should.equal(True)
}

// --- Config parsing ---

pub fn parse_enabled_on_test() {
  parse_enabled("1") |> should.equal(True)
}

pub fn parse_enabled_off_test() {
  parse_enabled("0") |> should.equal(False)
}

pub fn parse_enabled_garbage_test() {
  parse_enabled("yes") |> should.equal(False)
  parse_enabled("") |> should.equal(False)
  parse_enabled("true") |> should.equal(False)
}

pub fn parse_rollout_pct_normal_test() {
  parse_rollout_pct("50") |> should.equal(50)
  parse_rollout_pct("0") |> should.equal(0)
  parse_rollout_pct("100") |> should.equal(100)
}

pub fn parse_rollout_pct_clamp_test() {
  parse_rollout_pct("-5") |> should.equal(0)
  parse_rollout_pct("150") |> should.equal(100)
}

pub fn parse_rollout_pct_garbage_test() {
  parse_rollout_pct("abc") |> should.equal(0)
  parse_rollout_pct("") |> should.equal(0)
}

pub fn parse_override_values_test() {
  parse_override("on") |> should.equal(ForceOn)
  parse_override("off") |> should.equal(ForceOff)
  parse_override("") |> should.equal(NoOverride)
  parse_override("garbage") |> should.equal(NoOverride)
}

// --- Variant selection ---

pub fn variant_selects_first_when_bucket_in_range_test() {
  let flag =
    VariantFlag(
      name: "exp",
      enabled: True,
      variants: [
        VariantConfig(Variant("A"), 25),
        VariantConfig(Variant("B"), 75),
      ],
      fallback: Variant("control"),
    )
  // bucket for request_id:user-1 is below the first weight boundary
  select_variant(flag, ByRequestId("user-1"), NoOverride)
  |> should.equal(Variant("A"))
}

pub fn variant_selects_second_when_bucket_past_first_test() {
  let flag =
    VariantFlag(
      name: "exp",
      enabled: True,
      variants: [
        VariantConfig(Variant("A"), 40),
        VariantConfig(Variant("B"), 60),
      ],
      fallback: Variant("control"),
    )
  // bucket for request_id:user-2 lands in the second weight range
  select_variant(flag, ByRequestId("user-2"), NoOverride)
  |> should.equal(Variant("B"))
}

pub fn variant_falls_back_when_disabled_test() {
  let flag =
    VariantFlag(
      name: "exp",
      enabled: False,
      variants: [VariantConfig(Variant("A"), 100)],
      fallback: Variant("control"),
    )
  select_variant(flag, ByRequestId("user-1"), NoOverride)
  |> should.equal(Variant("control"))
}

pub fn variant_falls_back_when_no_variants_test() {
  let flag =
    VariantFlag(
      name: "exp",
      enabled: True,
      variants: [],
      fallback: Variant("control"),
    )
  select_variant(flag, ByRequestId("user-1"), NoOverride)
  |> should.equal(Variant("control"))
}

pub fn variant_falls_back_when_weights_dont_cover_bucket_test() {
  let b = bucket(ByRequestId("user-1"))
  let flag =
    VariantFlag(
      name: "exp",
      enabled: True,
      variants: [VariantConfig(Variant("A"), b)],
      fallback: Variant("control"),
    )
  // Using the bucket itself as the weight leaves this key exactly on the
  // fallback boundary because selection is strictly `< accumulated`.
  select_variant(flag, ByRequestId("user-1"), NoOverride)
  |> should.equal(Variant("control"))
}

pub fn variant_force_on_with_empty_variants_falls_back_test() {
  let flag =
    VariantFlag(
      name: "exp",
      enabled: False,
      variants: [],
      fallback: Variant("control"),
    )
  select_variant(flag, ByRequestId("user-1"), ForceOn)
  |> should.equal(Variant("control"))
}

pub fn variant_force_on_overrides_disabled_test() {
  let flag =
    VariantFlag(
      name: "exp",
      enabled: False,
      variants: [VariantConfig(Variant("A"), 100)],
      fallback: Variant("control"),
    )
  select_variant(flag, ByRequestId("user-1"), ForceOn)
  |> should.equal(Variant("A"))
}

pub fn variant_force_off_overrides_enabled_test() {
  let flag =
    VariantFlag(
      name: "exp",
      enabled: True,
      variants: [VariantConfig(Variant("A"), 100)],
      fallback: Variant("control"),
    )
  select_variant(flag, ByRequestId("user-1"), ForceOff)
  |> should.equal(Variant("control"))
}

pub fn variant_deterministic_test() {
  let flag =
    VariantFlag(
      name: "exp",
      enabled: True,
      variants: [
        VariantConfig(Variant("A"), 33),
        VariantConfig(Variant("B"), 33),
        VariantConfig(Variant("C"), 34),
      ],
      fallback: Variant("control"),
    )
  let v1 = select_variant(flag, ByRequestId("user-2"), NoOverride)
  let v2 = select_variant(flag, ByRequestId("user-2"), NoOverride)
  v1 |> should.equal(v2)
}

// --- Variant config parsing ---

pub fn parse_variant_configs_normal_test() {
  let cfgs = parse_variant_configs("A:50,B:30,C:20")
  cfgs
  |> should.equal([
    VariantConfig(Variant("A"), 50),
    VariantConfig(Variant("B"), 30),
    VariantConfig(Variant("C"), 20),
  ])
}

pub fn parse_variant_configs_empty_test() {
  parse_variant_configs("")
  |> should.equal([])
}

pub fn parse_variant_configs_skips_invalid_test() {
  // missing weight, zero weight, malformed — all skipped
  let cfgs = parse_variant_configs("A:50,bad,B:0,C:30")
  cfgs
  |> should.equal([
    VariantConfig(Variant("A"), 50),
    VariantConfig(Variant("C"), 30),
  ])
}

pub fn parse_variant_configs_single_test() {
  parse_variant_configs("only:100")
  |> should.equal([VariantConfig(Variant("only"), 100)])
}

// --- Decision metadata (observability) ---

pub fn describe_boolean_enabled_test() {
  let flag = Flag(name: "dark_mode", enabled: True, rollout_pct: 100)
  let desc = describe_boolean(flag, ByRequestId("user-1"), NoOverride)
  // "flag=dark_mode bucket=<n> result=1"
  string.starts_with(desc, "flag=dark_mode bucket=")
  |> should.equal(True)
  string.ends_with(desc, " result=1")
  |> should.equal(True)
}

pub fn describe_boolean_disabled_test() {
  let flag = Flag(name: "dark_mode", enabled: False, rollout_pct: 100)
  let desc = describe_boolean(flag, ByRequestId("user-1"), NoOverride)
  string.ends_with(desc, " result=0")
  |> should.equal(True)
}

pub fn describe_variant_test() {
  let flag =
    VariantFlag(
      name: "exp",
      enabled: True,
      variants: [VariantConfig(Variant("B"), 100)],
      fallback: Variant("control"),
    )
  let desc = describe_variant(flag, ByRequestId("user-1"), NoOverride)
  string.starts_with(desc, "flag=exp bucket=")
  |> should.equal(True)
  // Variant B covers 100%, so fallback=0
  string.ends_with(desc, " variant=B fallback=0")
  |> should.equal(True)
}

pub fn describe_variant_fallback_test() {
  let flag =
    VariantFlag(
      name: "exp",
      enabled: False,
      variants: [VariantConfig(Variant("A"), 100)],
      fallback: Variant("control"),
    )
  let desc = describe_variant(flag, ByRequestId("user-1"), NoOverride)
  string.ends_with(desc, " variant=control fallback=1")
  |> should.equal(True)
}
