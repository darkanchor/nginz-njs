import mlcache/model
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn describe(r: HTTPRequest) -> Nil {
  model.default_config()
  |> model.summary
  |> http.return_text(r, 200, _)
}

fn blocked(r: HTTPRequest) -> Nil {
  http.return_text(r, 501, model.blocked_message())
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
  |> ngx.merge("blocked", blocked)
}
