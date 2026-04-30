import gleam/javascript/promise.{type Promise}
import http_client/client.{Post}
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
    Error(_) -> {
      let _ = http.log(r, "http_client: unexpected client error")
      http.return_text(r, 502, "client error")
      promise.resolve(Nil)
    }
  }
}

fn request_demo(r: HTTPRequest) -> Nil {
  client.new("https://api.example.test/users")
  |> client.with_method(Post)
  |> client.with_header("Content-Type", "application/json")
  |> client.with_header("X-Request-Id", "req-001")
  |> client.with_bearer_token("demo-token")
  |> client.with_body("{\"name\": \"test\"}")
  |> client.with_query_param("page", "1")
  |> client.with_query_param("limit", "20")
  |> client.with_query_param("sort", "desc")
  |> client.with_timeout(5000)
  |> client.summary
  |> http.return_text(r, 200, _)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("demo", demo)
  |> ngx.merge("fetch_demo", fetch_demo)
  |> ngx.merge("request_demo", request_demo)
}
