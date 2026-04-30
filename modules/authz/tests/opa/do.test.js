import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

// Standard nginx only — no native modules required.
// The remote_check handler calls a mock OPA fixture on the same server via ngx.fetch().

const MODULE = "authz";
const CONF = join(import.meta.dir, "nginx.conf");

describe("authz — remote OPA decision point", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("OPA allow endpoint returns 204", async () => {
    const res = await fetch(`${TEST_URL}/remote-allow`, { method: "GET" });
    expect(res.status).toBe(204);
  });

  test("OPA deny endpoint returns 403", async () => {
    const res = await fetch(`${TEST_URL}/remote-deny`, { method: "GET" });
    expect(res.status).toBe(403);
  });

  test("missing endpoint fails closed (403)", async () => {
    const res = await fetch(`${TEST_URL}/remote-no-endpoint`, {
      method: "GET",
    });
    expect(res.status).toBe(403);
  });
});
