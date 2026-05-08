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

  test("traced_enrich returns JSON trace body with propagated trace headers", async () => {
    const res = await fetch(`${TEST_URL}/traced-enrich/`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    expect(res.headers.get("x-request-id")).toBe("trace-enrich-001");
    expect(res.headers.get("x-trace-id")).toBe("trace-enrich-001");

    const body = JSON.parse(await res.text());
    expect(body.trace_id).toBe("trace-enrich-001");
    expect(body.span_count).toBe(2);
    expect(body.spans.map((span) => span.name)).toEqual(["auth", "profile"]);
  });

  test("traced_enrich stays observational when a subrequest returns 500", async () => {
    const res = await fetch(`${TEST_URL}/traced-enrich-failing/`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    expect(res.headers.get("x-request-id")).toBe("trace-enrich-failing-001");

    const body = JSON.parse(await res.text());
    expect(body.trace_id).toBe("trace-enrich-failing-001");
    expect(body.spans.map((span) => span.name)).toEqual(["auth", "profile"]);

    const authSpan = body.spans.find((span) => span.name === "auth");
    const profileSpan = body.spans.find((span) => span.name === "profile");
    expect(authSpan.status).toBe(200);
    expect(authSpan.success).toBe(true);
    expect(profileSpan.status).toBe(500);
    expect(profileSpan.success).toBe(false);
  });

  test("traced_enrich records true Failed steps with status 0", async () => {
    const res = await fetch(`${TEST_URL}/traced-enrich-transport-failing/`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    expect(res.headers.get("x-request-id")).toBe(
      "trace-enrich-transport-failing-001",
    );

    const body = JSON.parse(await res.text());
    expect(body.trace_id).toBe("trace-enrich-transport-failing-001");
    expect(body.spans.map((span) => span.name)).toEqual([
      "auth",
      "profile",
      "transport_fail",
    ]);

    const failedSpan = body.spans.find((span) => span.name === "transport_fail");
    expect(failedSpan.status).toBe(0);
    expect(failedSpan.success).toBe(false);
  });
});
