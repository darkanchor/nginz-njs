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

describe("authz — session_gate", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE, ["session"]);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("returns 204 and X-Session-Subject for a live session", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=alice`);
    expect(startRes.status).toBe(204);
    const cookie = startRes.headers.get("set-cookie");
    expect(cookie).not.toBeNull();

    const gateRes = await fetch(`${TEST_URL}/gate`, {
      headers: { Cookie: cookie },
    });
    expect(gateRes.status).toBe(204);
    expect(gateRes.headers.get("x-session-subject")).toBe("alice");
  });

  test("returns 401 when the session cookie is missing", async () => {
    const res = await fetch(`${TEST_URL}/gate`);
    expect(res.status).toBe(401);
  });

  test("returns 401 for a malformed session cookie", async () => {
    const res = await fetch(`${TEST_URL}/gate`, {
      headers: { Cookie: "sid" },
    });
    expect(res.status).toBe(401);
  });

  test("returns 401 when the backing session entry has expired", async () => {
    const startRes = await fetch(`${TEST_URL}/start-short?subject=short`);
    expect(startRes.status).toBe(204);
    const cookie = startRes.headers.get("set-cookie");
    expect(cookie).not.toBeNull();

    await Bun.sleep(1100);

    const gateRes = await fetch(`${TEST_URL}/gate`, {
      headers: { Cookie: cookie },
    });
    expect(gateRes.status).toBe(401);
  });

  test("returns 503 when session_dict is unset", async () => {
    const res = await fetch(`${TEST_URL}/gate-no-dict`, {
      headers: { Cookie: "sid=abc123" },
    });
    expect(res.status).toBe(503);
  });
});
