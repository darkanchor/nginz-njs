import gleeunit
import gleeunit/should
import session/model

pub fn main() {
  gleeunit.main()
}

pub fn default_descriptor_summary_test() {
  model.default_descriptor()
  |> model.summary
  |> should.equal("sid backend=shared_dict ttl=3600 same_site=Lax")
}

pub fn blocked_message_test() {
  model.blocked_message()
  |> should.equal(
    "session runtime blocked until native shared_dict backing is available",
  )
}
