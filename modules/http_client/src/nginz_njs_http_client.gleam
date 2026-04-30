import gleam/javascript/promise.{type Promise}
import http_client/client
import http_client/fetch.{FetchFailed, Response, execute}
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn demo(r: HTTPRequest) -> Nil {
  client.demo_request()
  |> client.summary
  |> http.return_text(r, 200, _)
}

fn fetch_demo(r: HTTPRequest) -> Promise(Nil) {
  let req = client.new("http://127.0.0.1:8888/__fixture/upstream")
  use result <- promise.await(execute(req))
  case result {
    Ok(Response(status:, body:)) -> {
      http.return_text(r, status, body)
      promise.resolve(Nil)
    }
    Error(FetchFailed(reason)) -> {
      let _ = http.log(r, "http_client: fetch failed — " <> reason)
      http.return_text(r, 502, "fetch failed")
      promise.resolve(Nil)
    }
  }
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("demo", demo)
  |> ngx.merge("fetch_demo", fetch_demo)
}
