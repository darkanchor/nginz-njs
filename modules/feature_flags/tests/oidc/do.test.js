import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";
import { OIDCMock } from "../../../../submodules/nginz/tests/mocks/oidc.js";

const MODULE = "feature_flags";
const CONF = join(import.meta.dir, "nginx.conf");

let oidcMock = null;

function extractCookie(setCookie, name) {
  const match = setCookie?.match(new RegExp(`${name}=([^;]+)`));
  return match?.[1] ?? null;
}

// Full OIDC authorization code flow → returns the oidc_session value.
async function acquireOIDCSession(path) {
  const step1 = await fetch(`${TEST_URL}${path}`, { redirect: "manual" });
  expect(step1.status).toBe(302);
  const stateCookieValue = extractCookie(step1.headers.get("set-cookie"), "oidc_state");
  const authUrl = step1.headers.get("location");

  const step2 = await fetch(authUrl, { redirect: "manual" });
  expect(step2.status).toBe(302);
  const callbackUrl = step2.headers.get("location");

  const step3 = await fetch(callbackUrl, {
    redirect: "manual",
    headers: { Cookie: `oidc_state=${stateCookieValue}` },
  });
  expect(step3.status).toBe(302);
  return extractCookie(step3.headers.get("set-cookie"), "oidc_session");
}

describe("feature_flags — OIDC-derived user identity for bucketing", () => {
  beforeAll(async () => {
    oidcMock = new OIDCMock(9999).start();
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    oidcMock?.stop();
    cleanupRuntime(MODULE);
  });

  test("authenticated request uses OIDC subject for stable bucketing", async () => {
    const oidcSession = await acquireOIDCSession("/bucket/oidc?fallback=fb");

    const res = await fetch(`${TEST_URL}/bucket/oidc?fallback=fb`, {
      headers: { Cookie: `oidc_session=${oidcSession}` },
    });
    expect(res.status).toBe(200);
    const bucket = parseInt(await res.text(), 10);
    expect(bucket).toBeGreaterThanOrEqual(0);
    expect(bucket).toBeLessThan(100);

    // Same key "user1" via explicit user_id should produce the same bucket.
    const res2 = await fetch(`${TEST_URL}/bucket/user?id=user1`);
    expect(parseInt(await res2.text(), 10)).toBe(bucket);
  });

  test("unauthenticated request to OIDC endpoint redirects to authorize", async () => {
    const res = await fetch(`${TEST_URL}/bucket/oidc?fallback=fb`, { redirect: "manual" });
    expect(res.status).toBe(302);
    const location = new URL(res.headers.get("location"));
    expect(location.pathname).toBe("/authorize");
  });

  test("bucket is deterministic across two authenticated requests for the same user", async () => {
    const oidcSession = await acquireOIDCSession("/bucket/oidc?fallback=fb");

    const [r1, r2] = await Promise.all([
      fetch(`${TEST_URL}/bucket/oidc?fallback=fb`, { headers: { Cookie: `oidc_session=${oidcSession}` } }),
      fetch(`${TEST_URL}/bucket/oidc?fallback=fb`, { headers: { Cookie: `oidc_session=${oidcSession}` } }),
    ]);
    expect(await r1.text()).toBe(await r2.text());
  });
});
