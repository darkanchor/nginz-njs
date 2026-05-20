import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "authz";
const CONF = join(import.meta.dir, "nginx.conf");

const identityHeaders = {
  "X-Jwt-Role": "ops,support",
  "X-Oidc-Sub": "user-123",
  "X-Oidc-Email": "user@example.com",
  "X-Oidc-Name": "Example User",
  "X-Waf-Result": "dryrun",
  "X-Waf-Category": "sqli",
  "X-Waf-Rule-Id": "42",
  "X-Waf-Score": "70",
  "X-Nftset-Result": "allow",
  "X-Nftset-Matched-Set": "",
};

describe("authz — milestone 3 composed policy shell", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE, ["session"]);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("allows one decision flow over identity, session, query, security signals, and remote authz", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=alice`);
    expect(startRes.status).toBe(204);
    const cookie = startRes.headers.get("set-cookie");
    expect(cookie).not.toBeNull();

    const res = await fetch(`${TEST_URL}/milestone3?view=summary`, {
      headers: { ...identityHeaders, Cookie: cookie },
    });

    expect(res.status).toBe(204);
    expect(res.headers.get("x-authz-status")).toBe("allow");
    expect(res.headers.get("x-authz-decision-code")).toBe("204");
    expect(res.headers.get("x-authz-role")).toBe("ops,support");
    expect(res.headers.get("x-authz-session-subject")).toBe("alice");
    expect(res.headers.get("x-authz-query-view")).toBe("summary");
    expect(res.headers.get("x-authz-waf-result")).toBe("dryrun");
    expect(res.headers.get("x-authz-nftset-result")).toBe("allow");
  });

  test("denies when the session subject is absent and exposes structured deny context", async () => {
    const res = await fetch(`${TEST_URL}/milestone3?view=summary`, {
      headers: identityHeaders,
    });

    expect(res.status).toBe(401);
    expect(res.headers.get("x-authz-status")).toBe("deny");
    expect(res.headers.get("x-authz-decision-code")).toBe("401");
    expect(res.headers.get("x-authz-reason")).toBe(
      "missing required claim: session_subject",
    );
    expect(res.headers.get("x-authz-session-subject")).toBeNull();
  });

  test("denies when remote authz rejects after local checks pass", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=alice`);
    const cookie = startRes.headers.get("set-cookie");

    const res = await fetch(`${TEST_URL}/milestone3-remote-deny?view=full`, {
      headers: { ...identityHeaders, Cookie: cookie },
    });

    expect(res.status).toBe(403);
    expect(res.headers.get("x-authz-status")).toBe("deny");
    expect(res.headers.get("x-authz-decision-code")).toBe("403");
    expect(res.headers.get("x-authz-reason")).toBe("remote authz: denied");
    expect(res.headers.get("x-authz-session-subject")).toBe("alice");
  });

  test("fails closed on missing session dict configuration", async () => {
    const res = await fetch(`${TEST_URL}/milestone3-no-dict?view=summary`, {
      headers: identityHeaders,
    });

    expect(res.status).toBe(503);
    expect(res.headers.get("x-authz-status")).toBe("deny");
    expect(res.headers.get("x-authz-decision-code")).toBe("503");
    expect(res.headers.get("x-authz-reason")).toBe(
      "session dict not configured",
    );
  });
});
