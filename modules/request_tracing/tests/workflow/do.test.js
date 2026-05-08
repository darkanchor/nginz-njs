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

describe("request_tracing — traced_workflow", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("returns 204 with X-Request-ID propagated from $ngz_request_id", async () => {
    const res = await fetch(`${TEST_URL}/workflow/`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-request-id")).toBe("trace-workflow-001");
    expect(res.headers.get("x-trace-id")).toBe("trace-workflow-001");
  });

  test("trace ID is stable across repeated requests", async () => {
    const r1 = await fetch(`${TEST_URL}/workflow/`);
    const r2 = await fetch(`${TEST_URL}/workflow/`);
    expect(r1.headers.get("x-request-id")).toBe("trace-workflow-001");
    expect(r2.headers.get("x-request-id")).toBe("trace-workflow-001");
  });
});
