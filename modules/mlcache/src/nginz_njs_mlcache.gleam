import mlcache/model
import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}

fn describe(r: HTTPRequest) -> Nil {
  model.default_config()
  |> model.summary
  |> http.return_text(r, 200, _)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe", describe)
}
