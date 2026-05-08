import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "workflow";
const CONF = join(import.meta.dir, "nginx.conf");

describe("workflow — chain subrequest", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("chains through internal upstream and returns its body", async () => {
    const res = await fetch(`${TEST_URL}/chain`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("upstream-response");
  });

  test("delegates external fetch through http_client and returns its body", async () => {
    const res = await fetch(`${TEST_URL}/fetch-chain`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("fixture-response");
  });

  test("sequential runs two subrequests in order, joining bodies", async () => {
    const res = await fetch(`${TEST_URL}/sequential`);
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toContain("response-a");
    expect(body).toContain("response-b");
  });

  test("retry wrapper succeeds on first attempt", async () => {
    const res = await fetch(`${TEST_URL}/retry`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("upstream-response");
  });

  test("timeout wrapper may or may not timeout — check status is 200 or 504", async () => {
    const res = await fetch(`${TEST_URL}/timeout`);
    // With a 10ms timeout the subrequest may or may not finish in time
    expect([200, 504]).toContain(res.status);
  });

  test("recover demo returns fallback when upstream is unreliable", async () => {
    const res = await fetch(`${TEST_URL}/recover-demo`);
    // /internal/unreliable returns 500, so recover should give fallback
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("fallback-response");
  });

  test("first-ok demo returns one of the two upstream bodies", async () => {
    const res = await fetch(`${TEST_URL}/first-ok-demo`);
    expect(res.status).toBe(200);
    const body = await res.text();
    // Should be one of the upstream responses
    expect(["response-a", "response-b"]).toContain(body);
  });

  test("map-body demo uppercases the upstream response", async () => {
    const res = await fetch(`${TEST_URL}/map-body-demo`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("UPSTREAM-RESPONSE");
  });

  test("summary returns ok/fail counts", async () => {
    const res = await fetch(`${TEST_URL}/summary`);
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toMatch(/^ok=2 fail=0$/);
  });

  test("templated-parallel hands final shaping to response_templating", async () => {
    const res = await fetch(`${TEST_URL}/templated-parallel`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    expect(await res.json()).toEqual({
      upstream_a: "response-a",
      upstream_b: "response-b",
    });
  });

  test("degraded-parallel returns full JSON when both branches succeed", async () => {
    const res = await fetch(`${TEST_URL}/degraded-parallel`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    expect(await res.json()).toEqual({
      mode: "full",
      primary: "response-a",
      secondary: "response-b",
    });
  });

  test("degraded-parallel returns degraded JSON when only the secondary branch fails", async () => {
    const res = await fetch(`${TEST_URL}/degraded-parallel?secondary=fail`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    expect(await res.json()).toEqual({
      mode: "degraded",
      primary: "response-a",
      secondary: "fallback-secondary",
    });
  });

  test("degraded-parallel returns 502 when the required primary branch fails", async () => {
    const res = await fetch(`${TEST_URL}/degraded-parallel?primary=fail`);
    expect(res.status).toBe(502);
  });

  test("degraded-parallel still returns 502 when both branches fail because primary is required", async () => {
    const res = await fetch(`${TEST_URL}/degraded-parallel?primary=fail&secondary=fail`);
    expect(res.status).toBe(502);
  });
});
