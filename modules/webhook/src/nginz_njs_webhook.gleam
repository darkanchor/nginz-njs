import njs/http.{type HTTPRequest}
import njs/ngx.{type JsObject}
import webhook/spec

fn describe_outbound(r: HTTPRequest) -> Nil {
  spec.demo_outbound()
  |> spec.summary
  |> http.return_text(r, 200, _)
}

fn describe_inbound(r: HTTPRequest) -> Nil {
  spec.demo_inbound()
  |> spec.summary
  |> http.return_text(r, 200, _)
}

pub fn exports() -> JsObject {
  ngx.object()
  |> ngx.merge("describe_outbound", describe_outbound)
  |> ngx.merge("describe_inbound", describe_inbound)
}
