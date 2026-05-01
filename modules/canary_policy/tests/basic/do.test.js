import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "canary_policy";
const CONF = join(import.meta.dir, "nginx.conf");

describe("canary_policy — basic", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("canary request returns 204 with X-Canary header", async () => {
    const res = await fetch(`${TEST_URL}/api/canary`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-canary")).toBe("true");
  });

  test("stable request returns 204 with X-Canary header", async () => {
    const res = await fetch(`${TEST_URL}/api/stable`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-canary")).toBe("false");
  });

  test("unknown canary value passes through", async () => {
    const res = await fetch(`${TEST_URL}/api/unknown`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-canary")).toBe("unknown");
  });

  test("tagged canary response has X-Canary header", async () => {
    const res = await fetch(`${TEST_URL}/tagged/canary`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-canary")).toBe("true");
  });

  test("tagged stable response has X-Canary header", async () => {
    const res = await fetch(`${TEST_URL}/tagged/stable`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-canary")).toBe("false");
  });

  test("metrics handler returns 204", async () => {
    const res = await fetch(`${TEST_URL}/metrics/canary`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-canary")).toBe("true");
  });
});
