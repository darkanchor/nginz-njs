import feature_flags/evaluation.{
  type BucketKey, type Flag, type Variant, type VariantFlag, ByRemoteAddr,
  ByRequestId, ByUserId,
}
import metrics/helpers
import metrics/line.{type Metric, Tag}

pub fn boolean_decision(flag: Flag, key: BucketKey, enabled: Bool) -> Metric {
  helpers.increment("feature_flag_decision_total", [
    Tag(name: "flag", value: flag.name),
    Tag(name: "key_type", value: key_type(key)),
    helpers.tag_result(case enabled {
      True -> "enabled"
      False -> "disabled"
    }),
  ])
}

pub fn variant_selection(
  flag: VariantFlag,
  key: BucketKey,
  variant: Variant,
  is_fallback: Bool,
) -> Metric {
  helpers.increment("feature_flag_variant_total", [
    Tag(name: "flag", value: flag.name),
    Tag(name: "key_type", value: key_type(key)),
    Tag(name: "variant", value: variant.name),
    Tag(name: "fallback", value: bool_text(is_fallback)),
  ])
}

fn key_type(key: BucketKey) -> String {
  case key {
    ByRequestId(_) -> "request_id"
    ByUserId(_) -> "user_id"
    ByRemoteAddr(_) -> "remote_addr"
  }
}

fn bool_text(value: Bool) -> String {
  case value {
    True -> "1"
    False -> "0"
  }
}
