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
