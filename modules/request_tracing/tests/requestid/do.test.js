import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { existsSync, readFileSync } from "fs";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

// Requires nginx built with the native requestid module:
//   make   (the default NGINZ_MODULES includes requestid)

const MODULE = "request_tracing";
const CONF = join(import.meta.dir, "nginx.conf");
const ERROR_LOG = join(import.meta.dir, "../../../../dist/request_tracing/logs/error.log");
const UUID4_PATTERN =
  /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

async function waitForLog(needle, timeoutMs = 2000) {
  const startedAt = Date.now();

  while (Date.now() - startedAt < timeoutMs) {
    if (existsSync(ERROR_LOG)) {
      const content = readFileSync(ERROR_LOG, "utf8");
      if (content.includes(needle)) return content;
    }

    await Bun.sleep(50);
  }

  throw new Error(`timed out waiting for log content: ${needle}`);
}

describe("request_tracing — native requestid integration", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("traced uses native requestid UUID4 for both tracing headers", async () => {
    const res = await fetch(`${TEST_URL}/api/`);
    expect(res.status).toBe(204);

    const requestId = res.headers.get("x-request-id");
    const traceId = res.headers.get("x-trace-id");

    expect(requestId).toBeTruthy();
    expect(requestId).toMatch(UUID4_PATTERN);
    expect(traceId).toBe(requestId);
  });

  test("native requestid generates unique IDs per request", async () => {
    const ids = new Set();

    for (let i = 0; i < 5; i++) {
      const res = await fetch(`${TEST_URL}/api/`);
      expect(res.status).toBe(204);
      ids.add(res.headers.get("x-request-id"));
    }

    expect(ids.size).toBe(5);
  });

  test("incoming X-Request-ID is propagated through native requestid into tracing headers", async () => {
    const incomingId = "incoming-request-id-123";
    const res = await fetch(`${TEST_URL}/api/`, {
      headers: { "X-Request-ID": incomingId },
    });

    expect(res.status).toBe(204);
    expect(res.headers.get("x-request-id")).toBe(incomingId);
    expect(res.headers.get("x-trace-id")).toBe(incomingId);
  });

  test("traced_with_log also reads the native requestid value", async () => {
    const res = await fetch(`${TEST_URL}/log/`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-request-id")).toMatch(UUID4_PATTERN);
    expect(res.headers.get("x-trace-id")).toBe(res.headers.get("x-request-id"));
  });

  test("traced_with_log emits structured trace JSON with the propagated trace id", async () => {
    const incomingId = "trace-log-value-123";
    const res = await fetch(`${TEST_URL}/log/`, {
      headers: { "X-Request-ID": incomingId },
    });

    expect(res.status).toBe(204);
    expect(res.headers.get("x-request-id")).toBe(incomingId);
    expect(res.headers.get("x-trace-id")).toBe(incomingId);

    const log = await waitForLog(
      `request_tracing: {\"trace_id\":\"${incomingId}\",\"duration_ms\":0,\"span_count\":0,\"spans\":[]}`,
    );
    expect(log).toContain(`\"trace_id\":\"${incomingId}\"`);
  });

  test("traced_with_session also reads the native requestid value", async () => {
    const res = await fetch(`${TEST_URL}/correlated/`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-request-id")).toMatch(UUID4_PATTERN);
    expect(res.headers.get("x-trace-id")).toBe(res.headers.get("x-request-id"));
  });

  test("traced_with_session emits the correlation-oriented log path", async () => {
    const incomingId = "trace-correlation-456";
    const res = await fetch(`${TEST_URL}/correlated/`, {
      headers: { "X-Request-ID": incomingId },
    });

    expect(res.status).toBe(204);
    expect(res.headers.get("x-request-id")).toBe(incomingId);
    expect(res.headers.get("x-trace-id")).toBe(incomingId);

    const log = await waitForLog(
      `request_tracing: correlated — request_id=${incomingId}`,
    );
    expect(log).toContain(`request_tracing: correlated — request_id=${incomingId}`);
  });
});
