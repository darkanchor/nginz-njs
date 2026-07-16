import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

// Requires nginx built with the native jwt module:
//   make   (the default NGINZ_MODULES includes jwt)

const MODULE = "authz";
const CONF = join(import.meta.dir, "nginx.conf");
const JWT_SECRET = "nginz-test-secret";

async function makeJwt(claims) {
  const b64url = (v) =>
    btoa(JSON.stringify(v))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=/g, "");
  const header = b64url({ alg: "HS256", typ: "JWT" });
  const payload = b64url(claims);
  const msg = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(JWT_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(msg)
  );
  const sigB64 = btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
  return `${msg}.${sigB64}`;
}

function bearer(token) {
  return { headers: { Authorization: `Bearer ${token}` } };
}

describe("authz — JWT claim-based access via native jwt module", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  // Native jwt module verifies signature; njs jwt_check reads $jwt_claim_role
  test("admin role is allowed (njs policy)", async () => {
    const token = await makeJwt({ sub: "u1", role: "admin" });
    const res = await fetch(`${TEST_URL}/jwt-check`, bearer(token));
    expect(res.status).toBe(204);
  });

  test("user role is allowed (njs policy)", async () => {
    const token = await makeJwt({ sub: "u2", role: "user" });
    const res = await fetch(`${TEST_URL}/jwt-check`, bearer(token));
    expect(res.status).toBe(204);
  });

  test("guest role is denied by njs policy (403)", async () => {
    const token = await makeJwt({ sub: "u3", role: "guest" });
    const res = await fetch(`${TEST_URL}/jwt-check`, bearer(token));
    expect(res.status).toBe(403);
  });

  // These two are rejected by the native jwt module in the access phase (401)
  test("missing token rejected by native jwt module (401)", async () => {
    const res = await fetch(`${TEST_URL}/jwt-check`);
    expect(res.status).toBe(401);
  });

  test("tampered signature rejected by native jwt module (401)", async () => {
    const token = await makeJwt({ sub: "u4", role: "admin" });
    const parts = token.split(".");
    parts[2] = "dGFtcGVyZWQ"; // base64url "tampered"
    const res = await fetch(
      `${TEST_URL}/jwt-check`,
      bearer(parts.join("."))
    );
    expect(res.status).toBe(401);
  });
});
