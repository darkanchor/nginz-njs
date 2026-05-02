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

function cookieFrom(res) {
  const setCookie = res.headers.get("set-cookie");
  if (!setCookie) return null;
  const m = setCookie.match(/^sid=([^;]+)/);
  return m ? m[1] : null;
}

describe("session — sticky rollout assignment", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("get_canary returns 404 before any assignment is stored", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=user-a`);
    const sid = cookieFrom(startRes);
    expect(sid).not.toBeNull();

    const res = await fetch(`${TEST_URL}/canary/get`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(res.status).toBe(404);
  });

  test("set_canary stores assignment and get_canary returns it", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=user-b`);
    const sid = cookieFrom(startRes);

    // store canary=1
    const setRes = await fetch(`${TEST_URL}/canary/set?c=1`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(setRes.status).toBe(204);

    // read it back
    const getRes = await fetch(`${TEST_URL}/canary/get`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(getRes.status).toBe(200);
    expect(await getRes.text()).toBe("1");
  });

  test("set_canary rejects invalid assignment values", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=user-invalid`);
    const sid = cookieFrom(startRes);

    const setRes = await fetch(`${TEST_URL}/canary/set?c=true`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(setRes.status).toBe(400);

    const getRes = await fetch(`${TEST_URL}/canary/get`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(getRes.status).toBe(404);
  });

  test("set_canary rejects missing assignment values", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=user-missing`);
    const sid = cookieFrom(startRes);

    const setRes = await fetch(`${TEST_URL}/canary/set`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(setRes.status).toBe(400);
  });

  test("assignment is sticky — overwrite canary=0 and it persists", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=user-c`);
    const sid = cookieFrom(startRes);

    await fetch(`${TEST_URL}/canary/set?c=1`, {
      headers: { Cookie: `sid=${sid}` },
    });
    await fetch(`${TEST_URL}/canary/set?c=0`, {
      headers: { Cookie: `sid=${sid}` },
    });

    const getRes = await fetch(`${TEST_URL}/canary/get`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(await getRes.text()).toBe("0");
  });

  test("get_canary without cookie returns 404", async () => {
    const res = await fetch(`${TEST_URL}/canary/get`);
    expect(res.status).toBe(404);
  });

  test("end_session clears canary assignment", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=user-d`);
    const sid = cookieFrom(startRes);

    await fetch(`${TEST_URL}/canary/set?c=1`, {
      headers: { Cookie: `sid=${sid}` },
    });
    await fetch(`${TEST_URL}/end`, { headers: { Cookie: `sid=${sid}` } });

    // verify session also gone
    const verifyRes = await fetch(`${TEST_URL}/verify`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(verifyRes.status).toBe(401);

    // canary assignment gone too
    const getRes = await fetch(`${TEST_URL}/canary/get`, {
      headers: { Cookie: `sid=${sid}` },
    });
    expect(getRes.status).toBe(404);
  });
});
