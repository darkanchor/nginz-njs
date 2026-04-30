import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "feature_flags";
const CONF = join(import.meta.dir, "nginx.conf");

describe("feature_flags — dict-backed state via mlcache", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("evaluate with no dict entry falls back to nginx vars (disabled by default)", async () => {
    const res = await fetch(`${TEST_URL}/evaluate`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("0");
  });

  test("set_flag returns 200 ok", async () => {
    const res = await fetch(
      `${TEST_URL}/set-flag?name=test_flag&enabled=1&pct=100`,
    );
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("ok");
  });

  test("evaluate reads from dict after set (enabled=1, pct=100 → 1)", async () => {
    await fetch(`${TEST_URL}/set-flag?name=test_flag&enabled=1&pct=100`);
    const res = await fetch(`${TEST_URL}/evaluate`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("1");
  });

  test("evaluate reflects dict update (enabled=0 → 0)", async () => {
    await fetch(`${TEST_URL}/set-flag?name=test_flag&enabled=0&pct=100`);
    const res = await fetch(`${TEST_URL}/evaluate`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("0");
  });

  test("set_flag without name returns 400", async () => {
    const res = await fetch(`${TEST_URL}/set-flag?enabled=1&pct=50`);
    expect(res.status).toBe(400);
  });
});
