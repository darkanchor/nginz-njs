import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "authz";
const CONF = join(import.meta.dir, "nginx.conf");

describe("authz — js_access phase handlers", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  describe("access_check (sync, no body)", () => {
    test("allows GET — passes to content handler", async () => {
      const res = await fetch(`${TEST_URL}/access`, { method: "GET" });
      expect(res.status).toBe(200);
      expect(await res.text()).toBe("ok");
    });

    test("allows POST", async () => {
      const res = await fetch(`${TEST_URL}/access`, { method: "POST" });
      expect(res.status).toBe(200);
    });

    test("allows DELETE", async () => {
      const res = await fetch(`${TEST_URL}/access`, { method: "DELETE" });
      expect(res.status).toBe(200);
    });
  });

  describe("access_json_check (async, JSON body)", () => {
    test("allows when required field present", async () => {
      const res = await fetch(`${TEST_URL}/access/json`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "read", resource: "orders" }),
      });
      expect(res.status).toBe(200);
      expect(await res.text()).toBe("ok");
    });

    test("denies 401 when required field missing", async () => {
      const res = await fetch(`${TEST_URL}/access/json`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ resource: "orders" }),
      });
      expect(res.status).toBe(401);
    });

    test("allows with minimal body containing only required field", async () => {
      const res = await fetch(`${TEST_URL}/access/json`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "list" }),
      });
      expect(res.status).toBe(200);
    });

    test("rejects malformed JSON instead of falling through to content", async () => {
      const res = await fetch(`${TEST_URL}/access/json`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: "not-json",
      });
      expect(res.status).toBe(400);
      expect(await res.text()).not.toBe("ok");
    });

    test("fails closed on missing required-field configuration", async () => {
      const res = await fetch(`${TEST_URL}/access/json-misconfig`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "read", resource: "orders" }),
      });
      expect(res.status).toBe(500);
      expect(await res.text()).not.toBe("ok");
    });
  });

  describe("access_form_check (async, form body)", () => {
    test("allows when required field present", async () => {
      const form = new URLSearchParams({ action: "read", resource: "orders" });
      const res = await fetch(`${TEST_URL}/access/form`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      });
      expect(res.status).toBe(200);
      expect(await res.text()).toBe("ok");
    });

    test("denies 401 when required field missing", async () => {
      const form = new URLSearchParams({ resource: "orders" });
      const res = await fetch(`${TEST_URL}/access/form`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      });
      expect(res.status).toBe(401);
    });

    test("rejects unsupported form payloads instead of falling through to content", async () => {
      const res = await fetch(`${TEST_URL}/access/form`, {
        method: "POST",
        headers: { "Content-Type": "text/plain" },
        body: "action=read",
      });
      expect(res.status).toBe(400);
      expect(await res.text()).not.toBe("ok");
    });

    test("fails closed on missing required-field configuration", async () => {
      const form = new URLSearchParams({ action: "read", resource: "orders" });
      const res = await fetch(`${TEST_URL}/access/form-misconfig`, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: form.toString(),
      });
      expect(res.status).toBe(500);
      expect(await res.text()).not.toBe("ok");
    });
  });
});
