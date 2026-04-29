import gleam/javascript/promise.{type Promise}
import gleam/list
import gleam/string
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import workflow/pipeline.{Failed, Fetched, filter_ok, run, subrequest_step}

fn enrich(r: HTTPRequest) -> Promise(Nil) {
  let steps = [
    subrequest_step("/internal/auth"),
    subrequest_step("/internal/profile"),
  ]
  use results <- promise.await(run(r, steps))
  let pairs = filter_ok(results)
  let all_ok = list.all(pairs, fn(p) { p.0 >= 200 && p.0 < 300 })
  case all_ok {
    False -> {
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
    True -> {
      let bodies = list.map(pairs, fn(p) { p.1 })
      let combined = string.join(bodies, "\n")
      http.return_text(r, 200, combined)
      promise.resolve(Nil)
    }
  }
}

fn chain(r: HTTPRequest) -> Promise(Nil) {
  let step = subrequest_step("/internal/upstream")
  use result <- promise.await(step(r))
  case result {
    Fetched(200, body) -> {
      http.return_text(r, 200, body)
      promise.resolve(Nil)
    }
    Fetched(status, _) -> {
      http.return_code(r, status)
      promise.resolve(Nil)
    }
    Failed(reason) -> {
      let _ = http.log(r, "workflow: chain failed — " <> reason)
      http.return_code(r, 502)
      promise.resolve(Nil)
    }
  }
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("enrich", enrich)
  |> ngx.merge("chain", chain)
}
