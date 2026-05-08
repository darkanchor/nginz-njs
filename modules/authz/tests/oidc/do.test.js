import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

// Standard nginx only — no native modules required.
// $oidc_claim_* variables are simulated via nginx `set` from request headers.

const MODULE = "authz";
const CONF = join(import.meta.dir, "nginx.conf");

function oidcHeaders(sub, email = "", name = "") {
  const h = {};
  if (sub) h["X-Oidc-Sub"] = sub;
  if (email) h["X-Oidc-Email"] = email;
  if (name) h["X-Oidc-Name"] = name;
  return { headers: h };
}

describe("authz — OIDC identity normalization and claim-based policy", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  describe("oidc_check", () => {
    test("authenticated identity (sub present) → 204", async () => {
      const res = await fetch(
        `${TEST_URL}/oidc-check`,
        oidcHeaders("user-123", "user@example.com", "Test User")
      );
      expect(res.status).toBe(204);
    });

    test("missing sub → 401", async () => {
      const res = await fetch(`${TEST_URL}/oidc-check`);
      expect(res.status).toBe(401);
    });

    test("sub-only identity (email/name absent) → 204", async () => {
      const res = await fetch(`${TEST_URL}/oidc-check`, oidcHeaders("u-456"));
      expect(res.status).toBe(204);
    });
  });

  describe("enriched_oidc_check", () => {
    test("injects X-Authz-Status: allow when sub present", async () => {
      const res = await fetch(
        `${TEST_URL}/enriched-oidc-check`,
        oidcHeaders("user-789", "u@example.com", "Jane")
      );
      expect(res.status).toBe(204);
      expect(res.headers.get("x-authz-status")).toBe("allow");
    });

    test("injects OIDC claim headers on allow", async () => {
      const res = await fetch(
        `${TEST_URL}/enriched-oidc-check`,
        oidcHeaders("sub-001", "a@b.com", "Alice")
      );
      expect(res.headers.get("x-authz-sub")).toBe("sub-001");
      expect(res.headers.get("x-authz-email")).toBe("a@b.com");
      expect(res.headers.get("x-authz-name")).toBe("Alice");
    });

    test("injects X-Authz-Status: deny when sub missing", async () => {
      const res = await fetch(`${TEST_URL}/enriched-oidc-check`);
      expect(res.status).toBe(401);
      expect(res.headers.get("x-authz-status")).toBe("deny");
    });
  });
});
