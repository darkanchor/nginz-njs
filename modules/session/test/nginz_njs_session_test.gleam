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
