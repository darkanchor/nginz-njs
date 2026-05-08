import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

// Standard nginx only — no native modules required.

const MODULE = "authz";
const CONF = join(import.meta.dir, "nginx.conf");

describe("authz — downstream header injection", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  // enriched_check — local method rule with status header

  test("enriched_check allow: 204 + X-Authz-Status: allow", async () => {
    const res = await fetch(`${TEST_URL}/enriched-check`, { method: "GET" });
    expect(res.status).toBe(204);
    expect(res.headers.get("x-authz-status")).toBe("allow");
  });

  test("enriched_check deny (PURGE): 403 + X-Authz-Status: deny", async () => {
    const res = await fetch(`${TEST_URL}/enriched-check`, { method: "PURGE" });
    expect(res.status).toBe(403);
    expect(res.headers.get("x-authz-status")).toBe("deny");
  });

  // enriched_remote_check — OPA decision with status header

  test("enriched_remote_check allow: 204 + X-Authz-Status: allow", async () => {
    const res = await fetch(`${TEST_URL}/enriched-remote-allow`);
    expect(res.status).toBe(204);
    expect(res.headers.get("x-authz-status")).toBe("allow");
  });

  test("enriched_remote_check deny: 403 + X-Authz-Status: deny", async () => {
    const res = await fetch(`${TEST_URL}/enriched-remote-deny`);
    expect(res.status).toBe(403);
    expect(res.headers.get("x-authz-status")).toBe("deny");
  });

  test("enriched_composed_check allow: combines identity, query, waf, and nftset", async () => {
    const res = await fetch(`${TEST_URL}/enriched-composed-check?view=summary`, {
      headers: {
        "X-Jwt-Role": "ops,support",
        "X-Oidc-Sub": "user-123",
        "X-Oidc-Email": "user@example.com",
        "X-Oidc-Name": "Example User",
        "X-Waf-Result": "dryrun",
        "X-Waf-Category": "sqli",
        "X-Waf-Rule-Id": "42",
        "X-Waf-Score": "70",
        "X-Nftset-Result": "allow",
        "X-Nftset-Matched-Set": "",
      },
    });

    expect(res.status).toBe(204);
    expect(res.headers.get("x-authz-status")).toBe("allow");
    expect(res.headers.get("x-authz-role")).toBe("ops,support");
    expect(res.headers.get("x-authz-sub")).toBe("user-123");
    expect(res.headers.get("x-authz-email")).toBe("user@example.com");
    expect(res.headers.get("x-authz-waf-result")).toBe("dryrun");
    expect(res.headers.get("x-authz-waf-category")).toBe("sqli");
    expect(res.headers.get("x-authz-nftset-result")).toBe("allow");
  });

  test("enriched_composed_check deny: missing OIDC email returns 401 and still exposes intentional auth_request headers", async () => {
    const res = await fetch(`${TEST_URL}/enriched-composed-check?view=summary`, {
      headers: {
        "X-Jwt-Role": "admin",
        "X-Oidc-Sub": "user-123",
        "X-Waf-Result": "allowed",
        "X-Nftset-Result": "allow",
      },
    });

    expect(res.status).toBe(401);
    expect(res.headers.get("x-authz-status")).toBe("deny");
    expect(res.headers.get("x-authz-sub")).toBe("user-123");
    expect(res.headers.get("x-authz-email")).toBeNull();
    expect(res.headers.get("x-authz-role")).toBe("admin");
  });

  test("enriched_composed_check deny: role mismatch returns 403", async () => {
    const res = await fetch(`${TEST_URL}/enriched-composed-check?view=summary`, {
      headers: {
        "X-Jwt-Role": "guest",
        "X-Oidc-Sub": "user-123",
        "X-Oidc-Email": "user@example.com",
        "X-Waf-Result": "allowed",
        "X-Nftset-Result": "allow",
      },
    });

    expect(res.status).toBe(403);
    expect(res.headers.get("x-authz-status")).toBe("deny");
    expect(res.headers.get("x-authz-role")).toBe("guest");
  });

  test("enriched_composed_check deny: query mismatch returns 403", async () => {
    const res = await fetch(`${TEST_URL}/enriched-composed-check?view=detail`, {
      headers: {
        "X-Jwt-Role": "support",
        "X-Oidc-Sub": "user-123",
        "X-Oidc-Email": "user@example.com",
        "X-Waf-Result": "allowed",
        "X-Nftset-Result": "allow",
      },
    });

    expect(res.status).toBe(403);
    expect(res.headers.get("x-authz-status")).toBe("deny");
  });

  test("enriched_composed_check deny: waf decision returns 403 with waf headers", async () => {
    const res = await fetch(`${TEST_URL}/enriched-composed-check?view=full`, {
      headers: {
        "X-Jwt-Role": "admin",
        "X-Oidc-Sub": "user-123",
        "X-Oidc-Email": "user@example.com",
        "X-Waf-Result": "denied",
        "X-Waf-Category": "sqli",
        "X-Waf-Rule-Id": "99",
        "X-Waf-Score": "90",
        "X-Nftset-Result": "allow",
      },
    });

    expect(res.status).toBe(403);
    expect(res.headers.get("x-authz-status")).toBe("deny");
    expect(res.headers.get("x-authz-waf-result")).toBe("denied");
    expect(res.headers.get("x-authz-waf-category")).toBe("sqli");
  });

  test("enriched_composed_check deny: nftset decision returns 403 with nftset headers", async () => {
    const res = await fetch(`${TEST_URL}/enriched-composed-check?view=full`, {
      headers: {
        "X-Jwt-Role": "support",
        "X-Oidc-Sub": "user-123",
        "X-Oidc-Email": "user@example.com",
        "X-Waf-Result": "allowed",
        "X-Nftset-Result": "deny",
        "X-Nftset-Matched-Set": "blocklist",
      },
    });

    expect(res.status).toBe(403);
    expect(res.headers.get("x-authz-status")).toBe("deny");
    expect(res.headers.get("x-authz-nftset-result")).toBe("deny");
    expect(res.headers.get("x-authz-nftset-matched-set")).toBe("blocklist");
  });
});
