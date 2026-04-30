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
