import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "request_tracing";
const CONF = join(import.meta.dir, "nginx.conf");

describe("request_tracing — basic", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("propagates X-Request-ID and X-Trace-ID headers", async () => {
    const res = await fetch(`${TEST_URL}/api/`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-request-id")).toBe("test-request-123");
    expect(res.headers.get("x-trace-id")).toBe("test-request-123");
  });

  test("traced with log returns 204", async () => {
    const res = await fetch(`${TEST_URL}/log/`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-request-id")).toBe("test-request-456");
  });

  test("traced with session returns 204", async () => {
    const res = await fetch(`${TEST_URL}/correlated/`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-request-id")).toBe("test-request-789");
  });
});
