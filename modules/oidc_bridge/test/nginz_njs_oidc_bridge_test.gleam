import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit
import gleeunit/should
import oidc_bridge/claims
import oidc_bridge/feature_flags
import oidc_bridge/model.{bind, identity, identity_summary}
import oidc_bridge/session

pub fn main() {
  gleeunit.main()
}

// --- model tests ---

pub fn identity_test() {
  let id =
    identity("sub-1", "a@b.com", "Alice", [
      #("role", "admin"),
      #("group", "eng"),
    ])
  id.sub |> should.equal("sub-1")
  id.email |> should.equal("a@b.com")
  id.name |> should.equal("Alice")
  list.length(id.raw_claims) |> should.equal(2)
}

pub fn identity_summary_test() {
  let id = identity("sub-1", "a@b.com", "Alice", [])
  identity_summary(id)
  |> should.equal("sub=sub-1 email=a@b.com name=Alice")
}

pub fn bind_test() {
  let id = identity("sub-1", "a@b.com", "Alice", [])
  let binding = bind("sid-123", id, 1000)
  binding.session_id |> should.equal("sid-123")
  binding.identity.sub |> should.equal("sub-1")
  binding.created_at |> should.equal(1000)
}

// --- session tests ---

pub fn create_binding_test() {
  let id = identity("sub-1", "a@b.com", "Alice", [])
  let binding = session.create_binding(id, 1000)
  string.starts_with(binding.session_id, "oidc:sub-1:1000")
  |> should.equal(True)
}

pub fn session_subject_test() {
  let id = identity("sub-42", "", "", [])
  session.session_subject(id) |> should.equal("sub-42")
}

// --- claims tests ---

pub fn to_authz_claims_test() {
  let id =
    identity("sub-1", "a@b.com", "Alice", [
      #("role", "admin"),
    ])
  let authz_claims = claims.to_authz_claims(id)
  list.length(authz_claims) |> should.equal(4)
  // Check core claims are present
  let has_sub = list.any(authz_claims, fn(c) { c.0 == "sub" && c.1 == "sub-1" })
  has_sub |> should.equal(True)
}

pub fn has_claim_test() {
  let id =
    identity("sub-1", "a@b.com", "Alice", [
      #("role", "admin"),
    ])
  claims.has_claim(id, "sub") |> should.equal(True)
  claims.has_claim(id, "email") |> should.equal(True)
  claims.has_claim(id, "role") |> should.equal(True)
  claims.has_claim(id, "missing") |> should.equal(False)
}

pub fn get_claim_test() {
  let id =
    identity("sub-1", "a@b.com", "Alice", [
      #("role", "admin"),
    ])
  claims.get_claim(id, "sub") |> should.equal(Some("sub-1"))
  claims.get_claim(id, "email") |> should.equal(Some("a@b.com"))
  claims.get_claim(id, "role") |> should.equal(Some("admin"))
  claims.get_claim(id, "missing") |> should.equal(None)
}

// --- feature_flags tests ---

pub fn to_flag_key_test() {
  let id = identity("user-42", "", "", [])
  feature_flags.to_flag_key(id) |> should.equal("ByUserId:user-42")
}

pub fn to_flag_key_pair_test() {
  let id = identity("user-42", "", "", [])
  let pair = feature_flags.to_flag_key_pair(id)
  pair.0 |> should.equal("session")
  pair.1 |> should.equal("ByUserId:user-42")
}
