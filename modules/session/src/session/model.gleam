import gleam/int

pub type CookieConfig {
  CookieConfig(name: String, http_only: Bool, same_site: String)
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
  )
}

pub fn default_descriptor() -> SessionDescriptor {
  SessionDescriptor(
    cookie: CookieConfig(name: "sid", http_only: True, same_site: "Lax"),
    backend: SharedDict,
    ttl_seconds: 3600,
  )
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
  <> " same_site="
  <> descriptor.cookie.same_site
}
