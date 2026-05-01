//// Challenge page rendering. Produces HTML challenge pages for borderline
//// requests (CAPTCHA placeholder, login redirect, JS challenge).

import gleam/int

/// Render a simple HTML login redirect challenge page.
pub fn login_redirect(login_url: String) -> String {
  "<html><head><meta http-equiv=\"refresh\" content=\"0;url="
  <> login_url
  <> "\"></head><body>Redirecting to login...</body></html>"
}

/// Render a plain-text challenge response.
pub fn text_challenge(reason: String, challenge_type: String) -> String {
  "challenge: " <> challenge_type <> " — " <> reason
}

/// Render a JSON challenge response.
pub fn json_challenge(
  status: Int,
  reason: String,
  challenge_type: String,
) -> String {
  "{\"error\":\"challenge\",\"status\":"
  <> int.to_string(status)
  <> ",\"type\":\""
  <> challenge_type
  <> "\",\"reason\":\""
  <> reason
  <> "\"}"
}
