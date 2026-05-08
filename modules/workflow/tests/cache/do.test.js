import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "workflow";
const CONF = join(import.meta.dir, "nginx.conf");

describe("workflow — cached_step", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("first request hits upstream and returns its body", async () => {
    const res = await fetch(`${TEST_URL}/cached-workflow`);
    expect(res.status).toBe(201);
    expect(await res.text()).toBe("upstream-response");
  });

  test("second request preserves upstream status when served from cache", async () => {
    const res = await fetch(`${TEST_URL}/cached-workflow`);
    expect(res.status).toBe(201);
    expect(await res.text()).toBe("upstream-response");
  });

  test("stale-while-refresh first request returns upstream body", async () => {
    const res = await fetch(`${TEST_URL}/stale-demo`);
    expect(res.status).toBe(201);
    expect(await res.text()).toBe("upstream-response");
  });

  test("stale-while-refresh second request preserves upstream status", async () => {
    const res = await fetch(`${TEST_URL}/stale-demo`);
    expect(res.status).toBe(201);
    expect(await res.text()).toBe("upstream-response");
  });
});
