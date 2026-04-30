import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

// Requires njs built with js_shared_dict_zone support (standard njs build).

const MODULE = "authz";
const CONF = join(import.meta.dir, "nginx.conf");

function bearer(token) {
  return { headers: { Authorization: `Bearer ${token}` } };
}

describe("authz — cached remote OPA decision", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("allow decision returns 204 (cold cache)", async () => {
    const res = await fetch(`${TEST_URL}/cached-allow`, bearer("token-a"));
    expect(res.status).toBe(204);
  });

  test("allow decision returns 204 (warm cache, same token)", async () => {
    // Second request with the same token hits the cache
    const res = await fetch(`${TEST_URL}/cached-allow`, bearer("token-a"));
    expect(res.status).toBe(204);
  });

  test("deny decision returns 403 (cold cache)", async () => {
    const res = await fetch(`${TEST_URL}/cached-deny`, bearer("token-b"));
    expect(res.status).toBe(403);
  });

  test("deny decision returns 403 (warm cache, same token)", async () => {
    const res = await fetch(`${TEST_URL}/cached-deny`, bearer("token-b"));
    expect(res.status).toBe(403);
  });

  test("different tokens get independent decisions", async () => {
    const allow = await fetch(`${TEST_URL}/cached-allow`, bearer("token-x"));
    const deny = await fetch(`${TEST_URL}/cached-deny`, bearer("token-y"));
    expect(allow.status).toBe(204);
    expect(deny.status).toBe(403);
  });

  test("no token defers to OPA (allow mock → 204)", async () => {
    // Token presence enforcement is the OPA policy's job, not the cache handler's.
    // With the allow mock, requests without a Bearer token still get 204.
    const res = await fetch(`${TEST_URL}/cached-allow`);
    expect(res.status).toBe(204);
  });
});
