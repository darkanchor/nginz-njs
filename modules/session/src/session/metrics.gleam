import metrics/helpers
import metrics/line.{type Metric, Tag}

pub fn start() -> Metric {
  lifecycle("start", "success")
}

pub fn verify(success: Bool) -> Metric {
  lifecycle("verify", case success {
    True -> "success"
    False -> "failure"
  })
}

pub fn end_session() -> Metric {
  lifecycle("end", "success")
}

fn lifecycle(operation: String, result: String) -> Metric {
  helpers.increment("session_lifecycle_total", [
    Tag(name: "operation", value: operation),
    helpers.tag_result(result),
  ])
}
