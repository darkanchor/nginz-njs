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
      "GET https://example.internal/ping auth=Bearer demo-token timeout_ms=1500",
    );
  });

  test("fetch_demo performs a real fetch to another nginx location", async () => {
    const res = await fetch(`${TEST_URL}/fetch-demo`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("fixture-response");
  });
});
