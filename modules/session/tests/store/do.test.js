import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "session";
const CONF = join(import.meta.dir, "nginx.conf");

describe("session — store", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("start creates session and returns Set-Cookie", async () => {
    const res = await fetch(`${TEST_URL}/start?subject=alice`);
    expect(res.status).toBe(204);
    const setCookie = res.headers.get("set-cookie");
    expect(setCookie).not.toBeNull();
    expect(setCookie).toMatch(/^sid=[a-f0-9]{64}/);
  });

  test("verify with valid session returns 204 and X-Session-Subject", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=bob`);
    expect(startRes.status).toBe(204);
    const setCookie = startRes.headers.get("set-cookie");
    const match = setCookie.match(/^sid=([^;]+)/);
    expect(match).not.toBeNull();
    const sid = match[1];

    const verifyRes = await fetch(`${TEST_URL}/verify`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(verifyRes.status).toBe(204);
    expect(verifyRes.headers.get("x-session-subject")).toBe("bob");
  });

  test("verify without cookie returns 401", async () => {
    const res = await fetch(`${TEST_URL}/verify`);
    expect(res.status).toBe(401);
  });

  test("end clears the session cookie", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=carol`);
    const setCookie = startRes.headers.get("set-cookie");
    const match = setCookie.match(/^sid=([^;]+)/);
    const sid = match[1];

    const endRes = await fetch(`${TEST_URL}/end`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(endRes.status).toBe(204);
    expect(endRes.headers.get("set-cookie")).toMatch(/Max-Age=0/);
  });

  test("verify after end returns 401", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=dave`);
    const setCookie = startRes.headers.get("set-cookie");
    const match = setCookie.match(/^sid=([^;]+)/);
    const sid = match[1];

    await fetch(`${TEST_URL}/end`, { headers: { Cookie: `sid=${sid}` } });

    const verifyRes = await fetch(`${TEST_URL}/verify`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(verifyRes.status).toBe(401);
  });
});
