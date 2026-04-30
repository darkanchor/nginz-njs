import gleam/javascript/promise.{type Promise}
import gleam/list
import njs/http.{type HTTPRequest, type HTTPResponse}
import njs/ngx
import njs/response

pub type StepResult {
  Fetched(status: Int, body: String)
  Failed(reason: String)
}

pub type Step =
  fn(HTTPRequest) -> Promise(StepResult)

pub fn run(r: HTTPRequest, steps: List(Step)) -> Promise(List(StepResult)) {
  steps
  |> list.map(fn(step) { step(r) })
  |> promise.await_list
}

pub fn subrequest_step(path: String) -> Step {
  fn(r: HTTPRequest) -> Promise(StepResult) {
    use resp: HTTPResponse <- promise.await(http.subrequest(
      r,
      path,
      ngx.object(),
    ))
    promise.resolve(Fetched(http.status(resp), http.response_text(resp)))
  }
}

pub fn fetch_step(url: String) -> Step {
  fn(_r: HTTPRequest) -> Promise(StepResult) {
    use resp <- promise.await(ngx.fetch_url(url, ngx.object()))
    use body <- promise.await(response.text(resp))
    promise.resolve(Fetched(response.status(resp), body))
  }
}

pub fn map_result(
  result: StepResult,
  f: fn(Int, String) -> StepResult,
) -> StepResult {
  case result {
    Fetched(status, body) -> f(status, body)
    Failed(_) -> result
  }
}

pub fn filter_ok(results: List(StepResult)) -> List(#(Int, String)) {
  list.filter_map(results, fn(r) {
    case r {
      Fetched(status, body) -> Ok(#(status, body))
      Failed(_) -> Error(Nil)
    }
  })
}
