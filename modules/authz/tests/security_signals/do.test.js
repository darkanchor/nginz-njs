import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

// Standard nginx only — no native modules required.
// $waf_result / $nftset_result are simulated via nginx `set` from request headers.
// Tests exercise allow-path and dry-run composition; deny-path reconstruction
// through error_page is explicitly out of scope per the Milestone 2 design rule.

const MODULE = "authz";
const CONF = join(import.meta.dir, "nginx.conf");

describe("authz — WAF and nftset allow-path composition", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  describe("waf_check — allow-path", () => {
    test("waf result absent (module not active) → 204", async () => {
      const res = await fetch(`${TEST_URL}/waf-check`);
      expect(res.status).toBe(204);
    });

    test("waf result=allowed → 204", async () => {
      const res = await fetch(`${TEST_URL}/waf-check`, {
        headers: { "X-Waf-Result": "allowed" },
      });
      expect(res.status).toBe(204);
    });

    test("waf result=dryrun → 204 (observe only, do not block)", async () => {
      const res = await fetch(`${TEST_URL}/waf-check`, {
        headers: { "X-Waf-Result": "dryrun", "X-Waf-Category": "sqli" },
      });
      expect(res.status).toBe(204);
    });

    test("waf result=denied with category → 403", async () => {
      const res = await fetch(`${TEST_URL}/waf-check`, {
        headers: { "X-Waf-Result": "denied", "X-Waf-Category": "xss" },
      });
      expect(res.status).toBe(403);
    });

    test("waf result=denied without category → 403", async () => {
      const res = await fetch(`${TEST_URL}/waf-check`, {
        headers: { "X-Waf-Result": "denied" },
      });
      expect(res.status).toBe(403);
    });
  });

  describe("nftset_check — allow-path", () => {
    test("nftset result absent (module not active) → 204", async () => {
      const res = await fetch(`${TEST_URL}/nftset-check`);
      expect(res.status).toBe(204);
    });

    test("nftset result=allow → 204", async () => {
      const res = await fetch(`${TEST_URL}/nftset-check`, {
        headers: { "X-Nftset-Result": "allow" },
      });
      expect(res.status).toBe(204);
    });

    test("nftset result=deny with set name → 403", async () => {
      const res = await fetch(`${TEST_URL}/nftset-check`, {
        headers: {
          "X-Nftset-Result": "deny",
          "X-Nftset-Matched-Set": "blocklist",
        },
      });
      expect(res.status).toBe(403);
    });

    test("nftset result=deny without set name → 403", async () => {
      const res = await fetch(`${TEST_URL}/nftset-check`, {
        headers: { "X-Nftset-Result": "deny" },
      });
      expect(res.status).toBe(403);
    });
  });
});
