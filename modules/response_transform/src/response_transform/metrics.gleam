import gleam/int
import metrics/helpers
import metrics/line.{type Metric, Tag}

pub fn transform(status: Int) -> Metric {
  outcome("transformed", status)
}

pub fn passthrough(status: Int) -> Metric {
  outcome("passthrough", status)
}

fn outcome(result: String, status: Int) -> Metric {
  helpers.increment("response_transform_total", [
    helpers.tag_result(result),
    Tag(name: "status", value: int.to_string(status)),
  ])
}
