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

describe("authz — basic access check", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("allows GET", async () => {
    const res = await fetch(`${TEST_URL}/check`, { method: "GET" });
    expect(res.status).toBe(204);
  });

  test("allows POST", async () => {
    const res = await fetch(`${TEST_URL}/check`, { method: "POST" });
    expect(res.status).toBe(204);
  });

  test("allows DELETE", async () => {
    const res = await fetch(`${TEST_URL}/check`, { method: "DELETE" });
    expect(res.status).toBe(204);
  });
});
