import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";
import { OIDCMock } from "../../../../submodules/nginz/tests/mocks/oidc.js";

const MODULE = "session";
const CONF = join(import.meta.dir, "nginx.conf");

let oidcMock = null;

function extractCookie(setCookie, name) {
  const match = setCookie?.match(new RegExp(`${name}=([^;]+)`));
  return match?.[1] ?? null;
}

// Full OIDC authorization code flow → returns the sid cookie value.
async function doOIDCFlow() {
  // Step 1: request the OIDC-gated endpoint → oidc module redirects to mock
  const step1 = await fetch(`${TEST_URL}/session/start`, { redirect: "manual" });
  expect(step1.status).toBe(302);
  const stateCookieValue = extractCookie(step1.headers.get("set-cookie"), "oidc_state");
  const authUrl = step1.headers.get("location");

  // Step 2: mock authorize → redirects back to /callback with code
  const step2 = await fetch(authUrl, { redirect: "manual" });
  expect(step2.status).toBe(302);
  const callbackUrl = step2.headers.get("location");

  // Step 3: callback → oidc validates, sets oidc_session, redirects to /session/start
  const step3 = await fetch(callbackUrl, {
    redirect: "manual",
    headers: { Cookie: `oidc_state=${stateCookieValue}` },
  });
  expect(step3.status).toBe(302);
  const oidcSession = extractCookie(step3.headers.get("set-cookie"), "oidc_session");

  // Step 4: follow redirect to /session/start with oidc_session → start_oidc runs
  const step4 = await fetch(`${TEST_URL}/session/start`, {
    redirect: "manual",
    headers: { Cookie: `oidc_session=${oidcSession}` },
  });
  return { step4, oidcSession };
}

describe("session — OIDC-backed session start", () => {
  beforeAll(async () => {
    oidcMock = new OIDCMock(9999).start();
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    oidcMock?.stop();
    cleanupRuntime(MODULE);
  });

  test("OIDC flow issues a sid cookie with status 204", async () => {
    const { step4 } = await doOIDCFlow();
    expect(step4.status).toBe(204);
    const sid = extractCookie(step4.headers.get("set-cookie"), "sid");
    expect(sid).not.toBeNull();
  });

  test("session subject is oidc-prefixed claim sub", async () => {
    const { step4 } = await doOIDCFlow();
    const sid = extractCookie(step4.headers.get("set-cookie"), "sid");

    const verifyRes = await fetch(`${TEST_URL}/session/verify`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(verifyRes.status).toBe(204);
    expect(verifyRes.headers.get("x-session-subject")).toBe("oidc:user1");
  });

  test("end_session invalidates oidc-backed session", async () => {
    const { step4 } = await doOIDCFlow();
    const sid = extractCookie(step4.headers.get("set-cookie"), "sid");

    await fetch(`${TEST_URL}/session/end`, { headers: { Cookie: `sid=${sid}` } });

    const verifyRes = await fetch(`${TEST_URL}/session/verify`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(verifyRes.status).toBe(401);
  });

  test("unauthenticated request to /session/start redirects to OIDC authorize", async () => {
    const res = await fetch(`${TEST_URL}/session/start`, { redirect: "manual" });
    expect(res.status).toBe(302);
    const location = new URL(res.headers.get("location"));
    expect(location.hostname).toBe("127.0.0.1");
    expect(location.pathname).toBe("/authorize");
  });
});
