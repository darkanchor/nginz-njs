import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "security_gateway";
const CONF = join(import.meta.dir, "nginx.conf");

describe("security_gateway — basic", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("allow JWT authenticated request", async () => {
    const res = await fetch(`${TEST_URL}/allow/jwt`);
    expect(res.status).toBe(204);
  });

  test("allow OIDC authenticated request", async () => {
    const res = await fetch(`${TEST_URL}/allow/oidc`);
    expect(res.status).toBe(204);
  });

  test("deny anonymous request", async () => {
    const res = await fetch(`${TEST_URL}/deny/anonymous`);
    expect(res.status).toBe(401);
    const body = await res.json();
    expect(body.error).toBe("unauthorized");
  });

  test("deny rate-limited request", async () => {
    const res = await fetch(`${TEST_URL}/deny/ratelimited`);
    expect(res.status).toBe(429);
    const body = await res.json();
    expect(body.error).toBe("too_many_requests");
  });

  test("allow when rate limit is ok", async () => {
    const res = await fetch(`${TEST_URL}/allow/ratelimit_ok`);
    expect(res.status).toBe(204);
  });

  test("challenge redirects anonymous", async () => {
    const res = await fetch(`${TEST_URL}/challenge/anonymous`, { redirect: "manual" });
    expect(res.status).toBe(307);
  });

  test("challenge allows authenticated", async () => {
    const res = await fetch(`${TEST_URL}/challenge/authenticated`);
    expect(res.status).toBe(204);
  });

  test("metrics handler allows", async () => {
    const res = await fetch(`${TEST_URL}/metrics/allow`);
    expect(res.status).toBe(204);
  });
});
