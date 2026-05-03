pub fn ok(body: String) -> String {
  "ok " <> body
}

pub fn error(body: String) -> String {
  "error " <> body
}

pub fn kv(key: String, value: String) -> String {
  key <> "=" <> value
}
