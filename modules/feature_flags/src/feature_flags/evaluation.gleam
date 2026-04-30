import gleam/int
import gleam/list
import gleam/result
import gleam/string

pub type Flag {
  Flag(name: String, enabled: Bool, rollout_pct: Int)
}

pub type BucketKey {
  ByRequestId(String)
  ByUserId(String)
  ByRemoteAddr(String)
}

/// Per-request override that takes precedence over rollout percentage.
///
pub type Override {
  NoOverride
  ForceOn
  ForceOff
}

/// Full evaluation with override support.  `ForceOn` / `ForceOff` take
/// precedence; `NoOverride` falls through to `is_enabled`.
///
pub fn evaluate(flag: Flag, key: BucketKey, override: Override) -> Bool {
  case override {
    ForceOn -> True
    ForceOff -> False
    NoOverride -> is_enabled(flag, key)
  }
}

pub fn is_enabled(flag: Flag, key: BucketKey) -> Bool {
  flag.enabled && bucket(key) < flag.rollout_pct
}

pub fn bucket(key: BucketKey) -> Int {
  let id = case key {
    ByRequestId(id) -> id
    ByUserId(uid) -> uid
    ByRemoteAddr(addr) -> addr
  }
  fnv1a(id) |> int.remainder(100) |> result.unwrap(0) |> int.absolute_value
}

fn fnv1a(s: String) -> Int {
  let prime = 16_777_619
  let offset = 2_166_136_261
  let modulus = 4_294_967_296
  string.to_utf_codepoints(s)
  |> list.fold(offset, fn(hash, cp) {
    let xored = int.bitwise_exclusive_or(hash, string.utf_codepoint_to_int(cp))
    int.remainder(xored * prime, modulus) |> result.unwrap(0)
  })
}

/// --- Pure config parsing helpers ---
/// These are pure string → value conversions that work with any source
/// (nginx variables, file config, shared dict).
pub fn parse_enabled(raw: String) -> Bool {
  raw == "1"
}

pub fn parse_rollout_pct(raw: String) -> Int {
  let pct = result.unwrap(int.parse(raw), 0)
  case pct < 0 {
    True -> 0
    False ->
      case pct > 100 {
        True -> 100
        False -> pct
      }
  }
}

pub fn parse_override(raw: String) -> Override {
  case raw {
    "on" -> ForceOn
    "off" -> ForceOff
    _ -> NoOverride
  }
}

/// --- Variant (multi-arm) flags ---
pub type Variant {
  Variant(name: String)
}

pub type VariantConfig {
  VariantConfig(variant: Variant, weight: Int)
}

pub type VariantFlag {
  VariantFlag(
    name: String,
    enabled: Bool,
    variants: List(VariantConfig),
    fallback: Variant,
  )
}

/// Select a variant from a multi-arm flag.  If the flag is disabled returns
/// `fallback`.  Otherwise maps `bucket(key)` through the weighted variant
/// list (cumulative weights; any uncovered remainder goes to `fallback`).
///
pub fn select_variant(
  flag: VariantFlag,
  key: BucketKey,
  override: Override,
) -> Variant {
  case override {
    ForceOn -> select_from_configs(flag.variants, bucket(key), 0, flag.fallback)
    ForceOff -> flag.fallback
    NoOverride ->
      case flag.enabled {
        False -> flag.fallback
        True ->
          select_from_configs(flag.variants, bucket(key), 0, flag.fallback)
      }
  }
}

fn select_from_configs(
  configs: List(VariantConfig),
  bucket: Int,
  accumulated: Int,
  fallback: Variant,
) -> Variant {
  case configs {
    [] -> fallback
    [VariantConfig(variant:, weight:), ..rest] -> {
      let next = accumulated + weight
      case bucket < next {
        True -> variant
        False -> select_from_configs(rest, bucket, next, fallback)
      }
    }
  }
}

/// Parse variant configs from a compact string like `"A:50,B:30,C:20"`.
/// Each segment is `<name>:<weight>`.  Invalid segments are silently
/// skipped so that a misconfigured variant does not break evaluation.
///
pub fn parse_variant_configs(raw: String) -> List(VariantConfig) {
  case raw {
    "" -> []
    _ ->
      raw
      |> string.split(",")
      |> list.filter_map(fn(segment) {
        let parts = string.split(segment, ":")
        case parts {
          [name, weight_str] -> {
            let w = result.unwrap(int.parse(weight_str), 0)
            case w > 0 {
              True -> Ok(VariantConfig(Variant(name), w))
              False -> Error(Nil)
            }
          }
          _ -> Error(Nil)
        }
      })
  }
}

/// --- Decision metadata (observability) ---
pub type BooleanDecision {
  BooleanDecision(flag_name: String, bucket: Int, result: Bool)
}

pub type VariantDecision {
  VariantDecision(
    flag_name: String,
    bucket: Int,
    variant: Variant,
    is_fallback: Bool,
  )
}

/// Produce a deterministic summary line for a boolean flag decision.
/// Format: `"flag=<name> bucket=<n> result=<0|1>"`
///
pub fn describe_boolean(
  flag: Flag,
  key: BucketKey,
  override: Override,
) -> String {
  let b = bucket(key)
  let r = evaluate(flag, key, override)
  let r_str = case r {
    True -> "1"
    False -> "0"
  }
  "flag=" <> flag.name <> " bucket=" <> int.to_string(b) <> " result=" <> r_str
}

/// Produce a deterministic summary line for a variant flag decision.
/// Format: `"flag=<name> bucket=<n> variant=<name> fallback=<0|1>"`
///
pub fn describe_variant(
  flag: VariantFlag,
  key: BucketKey,
  override: Override,
) -> String {
  let b = bucket(key)
  let selected = select_variant(flag, key, override)
  let is_fb = case selected.name == flag.fallback.name {
    True -> "1"
    False -> "0"
  }
  "flag="
  <> flag.name
  <> " bucket="
  <> int.to_string(b)
  <> " variant="
  <> selected.name
  <> " fallback="
  <> is_fb
}
