import gleam/int

pub type CookieConfig {
  CookieConfig(
    name: String,
    http_only: Bool,
    secure: Bool,
    path: String,
    same_site: String,
  )
}

pub type StoreBackend {
  SharedDict
  RedisFallback
}

pub type SessionDescriptor {
  SessionDescriptor(
    cookie: CookieConfig,
    backend: StoreBackend,
    ttl_seconds: Int,
    rotate_after_seconds: Int,
  )
}

pub type DescriptorError {
  TtlNotPositive
  RotateNegative
}

pub fn default_descriptor() -> SessionDescriptor {
  SessionDescriptor(
    cookie: CookieConfig(
      name: "sid",
      http_only: True,
      secure: False,
      path: "/",
      same_site: "Lax",
    ),
    backend: SharedDict,
    ttl_seconds: 3600,
    rotate_after_seconds: 0,
  )
}

pub fn validate(
  descriptor: SessionDescriptor,
) -> Result(SessionDescriptor, DescriptorError) {
  case descriptor.ttl_seconds <= 0 {
    True -> Error(TtlNotPositive)
    False ->
      case descriptor.rotate_after_seconds < 0 {
        True -> Error(RotateNegative)
        False -> Ok(descriptor)
      }
  }
}

fn backend_text(backend: StoreBackend) -> String {
  case backend {
    SharedDict -> "shared_dict"
    RedisFallback -> "redis_fallback"
  }
}

pub fn summary(descriptor: SessionDescriptor) -> String {
  descriptor.cookie.name
  <> " backend="
  <> backend_text(descriptor.backend)
  <> " ttl="
  <> int.to_string(descriptor.ttl_seconds)
  <> " rotate="
  <> int.to_string(descriptor.rotate_after_seconds)
  <> " same_site="
  <> descriptor.cookie.same_site
}
