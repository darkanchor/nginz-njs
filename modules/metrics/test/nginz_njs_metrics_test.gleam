import gleeunit
import gleeunit/should
import metrics/line

pub fn main() {
  gleeunit.main()
}

pub fn render_statsd_demo_metric_test() {
  line.demo_metric()
  |> line.render_statsd
  |> should.equal("requests_total:1|c|#route:demo,status:200")
}

pub fn describe_demo_metric_test() {
  line.demo_metric()
  |> line.describe
  |> should.equal("requests_total type=c")
}
