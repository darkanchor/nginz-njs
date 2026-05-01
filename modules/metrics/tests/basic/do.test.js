import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "metrics";
const CONF = join(import.meta.dir, "nginx.conf");

describe("metrics — scaffold demo", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("describe returns stable metric summary", async () => {
    const res = await fetch(`${TEST_URL}/describe`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "nginz.requests_total type=c value=1 rate=1.0 tags=2",
    );
  });

  test("emit_demo returns stable statsd line", async () => {
    const res = await fetch(`${TEST_URL}/emit-demo`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "nginz.requests_total:1|c|#route:demo,status:200",
    );
  });

  test("emit_statsd from query params", async () => {
    const url = `${TEST_URL}/emit-statsd?name=http_requests&value=1&type=c&tags=route:/api,status:200`;
    const res = await fetch(url);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "nginz.http_requests:1|c|#route:/api,status:200",
    );
  });

  test("emit_dogstatsd from query params", async () => {
    const url = `${TEST_URL}/emit-dogstatsd?name=http_requests&value=1&type=c&tags=route:/api,status:200`;
    const res = await fetch(url);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "nginz.http_requests:1|c|#route:/api,status:200",
    );
  });

  test("validate_metric ok", async () => {
    const url = `${TEST_URL}/validate?name=req&value=1&type=c`;
    const res = await fetch(url);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("ok");
  });

  test("validate_metric rejects empty name", async () => {
    const url = `${TEST_URL}/validate?name=&value=1&type=c`;
    const res = await fetch(url);
    expect(res.status).toBe(400);
  });

  test("validate_metric rejects invalid chars in name", async () => {
    const url = `${TEST_URL}/validate?name=bad:name&value=1&type=c`;
    const res = await fetch(url);
    expect(res.status).toBe(400);
  });

  test("validate_metric rejects negative counter", async () => {
    const url = `${TEST_URL}/validate?name=req&value=-1&type=c`;
    const res = await fetch(url);
    expect(res.status).toBe(400);
  });

  test("describe_metric from query params", async () => {
    const url = `${TEST_URL}/describe-metric?name=req&value=1&type=c&tags=route:/api`;
    const res = await fetch(url);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("nginz.req type=c value=1 rate=1.0 tags=1");
  });

  test("emit_helper increment", async () => {
    const url = `${TEST_URL}/emit-helper?name=http_requests&pattern=increment&tags=route:/api,status:200`;
    const res = await fetch(url);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "nginz.http_requests:1|c|#route:/api,status:200",
    );
  });

  test("emit_helper error", async () => {
    const url = `${TEST_URL}/emit-helper?name=upstream_failure&pattern=error&tags=route:/api,status:502`;
    const res = await fetch(url);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "nginz.upstream_failure:1|c|#error:true,route:/api,status:502",
    );
  });

  test("emit_helper timing", async () => {
    const url = `${TEST_URL}/emit-helper?name=latency&value=42&pattern=timing&tags=route:/api`;
    const res = await fetch(url);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "nginz.latency:42|ms|#route:/api",
    );
  });
});
