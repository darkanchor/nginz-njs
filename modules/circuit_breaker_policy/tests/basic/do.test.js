import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "circuit_breaker_policy";
const CONF = join(import.meta.dir, "nginx.conf");

describe("circuit_breaker_policy — basic", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("closed circuit passes through (204)", async () => {
    const res = await fetch(`${TEST_URL}/api/closed`);
    expect(res.status).toBe(204);
  });

  test("open circuit blocks request (503)", async () => {
    const res = await fetch(`${TEST_URL}/api/open`);
    expect(res.status).toBe(503);
  });

  test("half-open circuit allows probe (204)", async () => {
    const res = await fetch(`${TEST_URL}/api/half-open`);
    expect(res.status).toBe(204);
  });

  test("unknown state passes through (204)", async () => {
    const res = await fetch(`${TEST_URL}/api/unknown`);
    expect(res.status).toBe(204);
  });

  test("fallback on open returns JSON error", async () => {
    const res = await fetch(`${TEST_URL}/fallback/open`);
    expect(res.status).toBe(503);
    expect(res.headers.get("content-type")).toBe("application/json");
    const body = await res.json();
    expect(body.error).toBe("service_unavailable");
    expect(body.circuit).toBe("open");
  });

  test("fallback on half-open returns degraded JSON", async () => {
    const res = await fetch(`${TEST_URL}/fallback/half-open`);
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.error).toBe("service_degraded");
    expect(body.circuit).toBe("half_open");
  });

  test("fallback on closed passes through", async () => {
    const res = await fetch(`${TEST_URL}/fallback/closed`);
    expect(res.status).toBe(204);
  });

  test("json error on open returns 503", async () => {
    const res = await fetch(`${TEST_URL}/json/open`);
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.circuit).toBe("open");
  });

  test("json error on closed passes through", async () => {
    const res = await fetch(`${TEST_URL}/json/closed`);
    expect(res.status).toBe(204);
  });
});
