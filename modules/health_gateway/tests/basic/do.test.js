import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "health_gateway";
const CONF = join(import.meta.dir, "nginx.conf");

describe("health_gateway — basic", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("aggregate all healthy returns 200", async () => {
    const res = await fetch(`${TEST_URL}/health/all-healthy`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("healthy");
    expect(body.backends).toHaveLength(2);
    expect(body.backends[0].healthy).toBe(true);
  });

  test("aggregate all unhealthy returns 503", async () => {
    const res = await fetch(`${TEST_URL}/health/all-unhealthy`);
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.status).toBe("unhealthy");
  });

  test("aggregate degraded returns 200", async () => {
    const res = await fetch(`${TEST_URL}/health/degraded`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("degraded");
    expect(body.backends).toHaveLength(2);
  });

  test("aggregate empty returns 503", async () => {
    const res = await fetch(`${TEST_URL}/health/empty`);
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.status).toBe("unhealthy");
  });

  test("readiness gate healthy returns 204", async () => {
    const res = await fetch(`${TEST_URL}/gate/healthy`);
    expect(res.status).toBe(204);
  });

  test("readiness gate unhealthy returns 503", async () => {
    const res = await fetch(`${TEST_URL}/gate/unhealthy`);
    expect(res.status).toBe(503);
    const body = await res.json();
    expect(body.ready).toBe(false);
  });

  test("custom health healthy returns 200", async () => {
    const res = await fetch(`${TEST_URL}/custom/healthy`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.status).toBe("healthy");
  });

  test("custom health unhealthy returns 503", async () => {
    const res = await fetch(`${TEST_URL}/custom/unhealthy`);
    expect(res.status).toBe(503);
  });
});
