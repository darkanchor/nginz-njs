import gleam/int
import gleam/javascript/promise.{type Promise}
import http_client/client.{Post}
import http_client/fetch.{
  FetchFailed, InvalidRequest, InvalidUrl, Response, Timeout, execute,
}
import http_client/middleware
import http_client/policy.{Retry, execute_with_policy, new, with_retry}
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
    Error(Timeout(ms)) -> {
      let _ =
        http.log(
          r,
          "http_client: fetch timed out — " <> int.to_string(ms) <> "ms",
        )
      http.return_text(r, 504, "timeout after " <> int.to_string(ms) <> "ms")
      promise.resolve(Nil)
    }
    Error(InvalidUrl(url)) -> {
      let _ = http.log(r, "http_client: invalid url — " <> url)
      http.return_text(r, 400, "invalid url: " <> url)
      promise.resolve(Nil)
    }
    Error(InvalidRequest(reason)) -> {
      let _ = http.log(r, "http_client: invalid request — " <> reason)
      http.return_text(r, 400, reason)
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

fn middleware_demo(r: HTTPRequest) -> Nil {
  let mw =
    middleware.stack([
      middleware.bearer_token("demo-token"),
      middleware.add_header("X-Request-Id", "req-mw"),
      middleware.json_content_type(),
      middleware.timeout_ms(3000),
    ])
  client.new("https://api.example.test/items")
  |> middleware.apply(mw)
  |> client.with_method(Post)
  |> client.summary
  |> http.return_text(r, 200, _)
}

fn retry_demo(r: HTTPRequest) -> Promise(Nil) {
  let req = client.new("http://127.0.0.1:8888/__fixture/upstream")
  let policy = new() |> with_retry(Retry(max_attempts: 3))
  use result <- promise.await(execute_with_policy(req, policy))
  case result {
    Ok(Response(status:, body:)) -> {
      http.return_text(r, status, body)
      promise.resolve(Nil)
    }
    Error(FetchFailed(reason)) -> {
      let _ = http.log(r, "http_client: retry exhausted — " <> reason)
      http.return_text(r, 502, "retry exhausted")
      promise.resolve(Nil)
    }
    Error(Timeout(ms)) -> {
      let _ =
        http.log(
          r,
          "http_client: retry timed out — " <> int.to_string(ms) <> "ms",
        )
      http.return_text(r, 504, "timeout after " <> int.to_string(ms) <> "ms")
      promise.resolve(Nil)
    }
    Error(InvalidUrl(url)) -> {
      let _ = http.log(r, "http_client: retry invalid url — " <> url)
      http.return_text(r, 400, "invalid url: " <> url)
      promise.resolve(Nil)
    }
    Error(InvalidRequest(reason)) -> {
      let _ = http.log(r, "http_client: retry invalid request — " <> reason)
      http.return_text(r, 400, reason)
      promise.resolve(Nil)
    }
  }
}

fn invalid_url_demo(r: HTTPRequest) -> Promise(Nil) {
  let req = client.new("ftp://example.invalid")
  use result <- promise.await(execute(req))
  case result {
    Error(InvalidUrl(url)) -> {
      http.return_text(r, 400, "invalid url: " <> url)
      promise.resolve(Nil)
    }
    Error(_) -> {
      http.return_text(r, 500, "unexpected error")
      promise.resolve(Nil)
    }
    Ok(_) -> {
      http.return_text(r, 500, "expected invalid url")
      promise.resolve(Nil)
    }
  }
}

fn invalid_request_demo(r: HTTPRequest) -> Promise(Nil) {
  let req = client.new("https://api.example.test") |> client.with_timeout(0)
  use result <- promise.await(execute(req))
  case result {
    Error(InvalidRequest(reason)) -> {
      http.return_text(r, 400, reason)
      promise.resolve(Nil)
    }
    Error(_) -> {
      http.return_text(r, 500, "unexpected error")
      promise.resolve(Nil)
    }
    Ok(_) -> {
      http.return_text(r, 500, "expected invalid request")
      promise.resolve(Nil)
    }
  }
}

fn timeout_demo(r: HTTPRequest) -> Promise(Nil) {
  let req =
    client.new("http://127.0.0.1:8888/__fixture/slow")
    |> client.with_timeout(10)
  use result <- promise.await(execute(req))
  case result {
    Error(Timeout(ms)) -> {
      http.return_text(r, 504, "timeout after " <> int.to_string(ms) <> "ms")
      promise.resolve(Nil)
    }
    Error(_) -> {
      http.return_text(r, 500, "unexpected error")
      promise.resolve(Nil)
    }
    Ok(_) -> {
      http.return_text(r, 500, "expected timeout")
      promise.resolve(Nil)
    }
  }
}

fn slow_fixture(r: HTTPRequest) -> Promise(Nil) {
  use _ <- promise.await(promise.wait(50))
  http.return_text(r, 200, "slow-response")
  promise.resolve(Nil)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("demo", demo)
  |> ngx.merge("fetch_demo", fetch_demo)
  |> ngx.merge("request_demo", request_demo)
  |> ngx.merge("middleware_demo", middleware_demo)
  |> ngx.merge("retry_demo", retry_demo)
  |> ngx.merge("invalid_url_demo", invalid_url_demo)
  |> ngx.merge("invalid_request_demo", invalid_request_demo)
  |> ngx.merge("timeout_demo", timeout_demo)
  |> ngx.merge("slow_fixture", slow_fixture)
}
