import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "http_client";
const CONF = join(import.meta.dir, "nginx.conf");

describe("http_client — scaffold demo", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("demo handler returns stable request summary", async () => {
    const res = await fetch(`${TEST_URL}/demo`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "GET https://example.internal/ping auth=Bearer demo-token timeout_ms=1500 body=none headers=0",
    );
  });

  test("fetch_demo performs a real fetch to another nginx location", async () => {
    const res = await fetch(`${TEST_URL}/fetch-demo`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("fixture-response");
  });

  test("request_demo returns full builder pipeline summary", async () => {
    const res = await fetch(`${TEST_URL}/request-demo`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "POST https://api.example.test/users?page=1&limit=20&sort=desc auth=Bearer demo-token timeout_ms=5000 body=some headers=2 qs=3pairs",
    );
  });

  test("middleware_demo returns stacked middleware summary", async () => {
    const res = await fetch(`${TEST_URL}/middleware-demo`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "POST https://api.example.test/items auth=Bearer demo-token timeout_ms=3000 body=none headers=2",
    );
  });

  test("retry_demo performs fetch with retry policy (succeeds first attempt)", async () => {
    const res = await fetch(`${TEST_URL}/retry-demo`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("fixture-response");
  });

  test("invalid_url_demo returns typed invalid url error", async () => {
    const res = await fetch(`${TEST_URL}/invalid-url-demo`);
    expect(res.status).toBe(400);
    expect(await res.text()).toBe("invalid url: ftp://example.invalid");
  });

  test("invalid_request_demo returns typed invalid request error", async () => {
    const res = await fetch(`${TEST_URL}/invalid-request-demo`);
    expect(res.status).toBe(400);
    expect(await res.text()).toBe("timeout_ms must be > 0, got 0");
  });

  test("timeout_demo returns typed timeout error", async () => {
    const res = await fetch(`${TEST_URL}/timeout-demo`);
    expect(res.status).toBe(504);
    expect(await res.text()).toBe("timeout after 10ms");
  });
});
