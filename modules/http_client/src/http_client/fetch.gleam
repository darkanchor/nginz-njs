import gleam/javascript/array
import gleam/javascript/promise.{type Promise}
import gleam/option.{None, Some}
import gleam/string
import http_client/client
import njs/headers
import njs/ngx
import njs/request
import njs/response

pub type Response {
  Response(status: Int, body: String)
}

pub type ClientError {
  FetchFailed(reason: String)
}

fn build_headers(req: client.Request) -> headers.Headers {
  let pairs = case req.auth_header {
    Some(value) -> [#("Authorization", value)]
    None -> []
  }
  headers.from_array(array.from_list(pairs))
}

fn to_runtime_request(req: client.Request) -> request.Request {
  request.from_url(
    req.url,
    request.EmptyRequestOption(
      headers: build_headers(req),
      method: client.method_text(req.method),
    ),
  )
}

pub fn execute(req: client.Request) -> Promise(Result(Response, ClientError)) {
  let fetch_promise =
    req
    |> to_runtime_request
    |> ngx.fetch_request(Nil)
    |> promise.await(fn(resp) {
      use body <- promise.await(response.text(resp))
      promise.resolve(Ok(Response(status: response.status(resp), body: body)))
    })

  promise.rescue(fetch_promise, fn(error) {
    Error(FetchFailed(string.inspect(error)))
  })
}
