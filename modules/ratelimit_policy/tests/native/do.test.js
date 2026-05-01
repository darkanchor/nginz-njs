import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "ratelimit_policy";
const CONF = join(import.meta.dir, "nginx.conf");

describe("ratelimit_policy — native", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  // -------------------------------------------------------------------
  // Custom JSON error on deny (Pattern A)
  // -------------------------------------------------------------------

  describe("custom JSON error on deny", () => {
    test("requests within limit (2r/s) are allowed", async () => {
      await Bun.sleep(1100); // fresh 1-second window
      const results = [];
      for (let i = 0; i < 2; i++) {
        const res = await fetch(`${TEST_URL}/api/`);
        results.push(res.status);
      }
      expect(results).toEqual([200, 200]);
    });

    test("rate-limited request returns custom JSON 429", async () => {
      await Bun.sleep(1100);
      // consume the 2r/s allowance
      await fetch(`${TEST_URL}/api/`);
      await fetch(`${TEST_URL}/api/`);
      // third request exceeds limit — native module returns 429 in ACCESS,
      // error_page redirects to js_content for custom error body
      const res = await fetch(`${TEST_URL}/api/`);
      expect(res.status).toBe(429);
      expect(res.headers.get("content-type")).toBe("application/json");
      const body = await res.json();
      expect(body.error).toBe("too_many_requests");
      expect(body.message).toContain("Rate limit exceeded");
      expect(body.retry_after).toBe(60);
    });

    test("resets after window expires", async () => {
      await Bun.sleep(1100);
      // exhaust the limit
      await fetch(`${TEST_URL}/api/`);
      await fetch(`${TEST_URL}/api/`);
      // should be denied now
      const denied = await fetch(`${TEST_URL}/api/`);
      expect(denied.status).toBe(429);

      // wait for fresh window
      await Bun.sleep(1100);
      // should be allowed again
      const reset = await fetch(`${TEST_URL}/api/`);
      expect(reset.status).toBe(200);
    });
  });

  // -------------------------------------------------------------------
  // Headers on deny (Pattern B)
  // -------------------------------------------------------------------

  describe("rate limit headers on deny", () => {
    test("denied request includes Retry-After and rate limit headers", async () => {
      await Bun.sleep(1100);
      // consume allowance
      await fetch(`${TEST_URL}/headers/`);
      await fetch(`${TEST_URL}/headers/`);
      // denied
      const res = await fetch(`${TEST_URL}/headers/`);
      expect(res.status).toBe(429);
      expect(res.headers.get("retry-after")).toBe("60");
      expect(res.headers.get("x-ratelimit-remaining")).toBe("0");
      expect(res.headers.get("x-ratelimit-reset")).toBe("60");
    });

    test("allowed request does not include Retry-After", async () => {
      await Bun.sleep(1100);
      const res = await fetch(`${TEST_URL}/headers/`);
      expect(res.status).toBe(200);
      expect(res.headers.get("retry-after")).toBeNull();
    });
  });

  // -------------------------------------------------------------------
  // Basic handler (Pattern C)
  // -------------------------------------------------------------------

  describe("basic handler (status only)", () => {
    test("allowed request returns 200", async () => {
      await Bun.sleep(1100);
      const res = await fetch(`${TEST_URL}/basic/`);
      expect(res.status).toBe(200);
    });

    test("denied request returns 429 (no custom body)", async () => {
      await Bun.sleep(1100);
      await fetch(`${TEST_URL}/basic/`);
      await fetch(`${TEST_URL}/basic/`);
      const res = await fetch(`${TEST_URL}/basic/`);
      expect(res.status).toBe(429);
      // basic handler returns no body (return_code only)
      const body = await res.text();
      expect(body).toBe("");
    });
  });

  // -------------------------------------------------------------------
  // Isolation between locations
  // -------------------------------------------------------------------

  describe("rate limit isolation", () => {
    test("separate locations have independent counters", async () => {
      await Bun.sleep(1100);

      // exhaust /api/
      await fetch(`${TEST_URL}/api/`);
      await fetch(`${TEST_URL}/api/`);
      const apiDenied = await fetch(`${TEST_URL}/api/`);
      expect(apiDenied.status).toBe(429);

      // /basic/ should still be fresh (separate location → separate bucket)
      const basicAllowed = await fetch(`${TEST_URL}/basic/`);
      expect(basicAllowed.status).toBe(200);
    });
  });

  // -------------------------------------------------------------------
  // Shared-memory enforcement (worker_processes 2)
  // -------------------------------------------------------------------

  describe("cross-worker enforcement", () => {
    test("shared counters enforce limit across workers", async () => {
      await Bun.sleep(1100);

      // send 4 concurrent requests — only 2 should be allowed (2r/s limit)
      const statuses = await Promise.all(
        Array.from({ length: 4 }, () =>
          fetch(`${TEST_URL}/api/`).then((r) => r.status)
        )
      );

      const allowed = statuses.filter((s) => s === 200);
      const denied = statuses.filter((s) => s === 429);
      expect(allowed.length).toBe(2);
      expect(denied.length).toBe(2);
    });
  });
});
