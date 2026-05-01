import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "ratelimit_policy";
const CONF = join(import.meta.dir, "nginx.conf");

describe("ratelimit_policy — basic", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("allowed request returns 204", async () => {
    const res = await fetch(`${TEST_URL}/api/allowed`);
    expect(res.status).toBe(204);
  });

  test("denied request returns 429", async () => {
    const res = await fetch(`${TEST_URL}/api/denied`);
    expect(res.status).toBe(429);
  });

  test("unknown result passes through as 204", async () => {
    const res = await fetch(`${TEST_URL}/api/unknown`);
    expect(res.status).toBe(204);
  });

  test("allowed with headers returns 204", async () => {
    const res = await fetch(`${TEST_URL}/headers/allowed`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-ratelimit-limit")).toBe("100");
    expect(res.headers.get("x-ratelimit-remaining")).toBe("99");
  });

  test("denied with headers returns 429 with Retry-After", async () => {
    const res = await fetch(`${TEST_URL}/headers/denied`);
    expect(res.status).toBe(429);
    expect(res.headers.get("retry-after")).toBe("60");
    expect(res.headers.get("x-ratelimit-remaining")).toBe("0");
  });

  test("custom error returns JSON body", async () => {
    const res = await fetch(`${TEST_URL}/custom/denied`);
    expect(res.status).toBe(429);
    expect(res.headers.get("content-type")).toBe("application/json");
    const body = await res.json();
    expect(body.error).toBe("too_many_requests");
    expect(body.retry_after).toBe(60);
  });

  test("fallback returns 429 with degraded body", async () => {
    const res = await fetch(`${TEST_URL}/fallback/denied`);
    expect(res.status).toBe(429);
    const body = await res.json();
    expect(body.error).toBe("too_many_requests");
    expect(body.message).toContain("degraded");
  });
});
