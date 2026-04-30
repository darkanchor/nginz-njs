import gleeunit
import gleeunit/should
import mlcache/model

pub fn main() {
  gleeunit.main()
}

pub fn default_config_summary_test() {
  model.default_config()
  |> model.summary
  |> should.equal("shared_dict policy=refresh_on_miss ttl=60")
}

pub fn blocked_message_test() {
  model.blocked_message()
  |> should.equal(
    "mlcache runtime blocked until native shared_dict backing is available",
  )
}
