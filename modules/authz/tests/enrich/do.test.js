import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

// Standard nginx only — no native modules required.

const MODULE = "authz";
const CONF = join(import.meta.dir, "nginx.conf");

describe("authz — downstream header injection", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  // enriched_check — local method rule with status header

  test("enriched_check allow: 204 + X-Authz-Status: allow", async () => {
    const res = await fetch(`${TEST_URL}/enriched-check`, { method: "GET" });
    expect(res.status).toBe(204);
    expect(res.headers.get("x-authz-status")).toBe("allow");
  });

  test("enriched_check deny (PURGE): 403 + X-Authz-Status: deny", async () => {
    const res = await fetch(`${TEST_URL}/enriched-check`, { method: "PURGE" });
    expect(res.status).toBe(403);
    expect(res.headers.get("x-authz-status")).toBe("deny");
  });

  // enriched_remote_check — OPA decision with status header

  test("enriched_remote_check allow: 204 + X-Authz-Status: allow", async () => {
    const res = await fetch(`${TEST_URL}/enriched-remote-allow`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-authz-status")).toBe("allow");
  });

  test("enriched_remote_check deny: 403 + X-Authz-Status: deny", async () => {
    const res = await fetch(`${TEST_URL}/enriched-remote-deny`);
    expect(res.status).toBe(403);
    expect(res.headers.get("x-authz-status")).toBe("deny");
  });
});
