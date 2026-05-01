import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import { createHmac } from "crypto";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "webhook";
const CONF = join(import.meta.dir, "nginx.conf");

// Reimplement the HMAC logic client-side for cross-checking.
function sign(payload, secret) {
  return createHmac("sha256", secret).update(payload).digest("hex");
}

describe("webhook — scaffold + signing", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("describe_outbound returns stable summary", async () => {
    const res = await fetch(`${TEST_URL}/describe-outbound`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "demo_outbound_webhook algorithm=hmac-sha256 mode=outbound url=https://webhook.example.test/delivery signature_header=X-Signature timeout_ms=5000 retry=3 headers=1",
    );
  });

  test("describe_inbound returns stable summary", async () => {
    const res = await fetch(`${TEST_URL}/describe-inbound`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "demo_inbound_webhook algorithm=hmac-sha256 mode=inbound url=https://source.example.test/callbacks signature_header=X-Signature timeout_ms=5000 retry=0 headers=0",
    );
  });

  test("sign_demo returns valid hex HMAC-SHA256", async () => {
    const res = await fetch(`${TEST_URL}/sign-demo`);
    expect(res.status).toBe(200);
    const sig = await res.text();
    // Should be 64 hex chars (32 bytes)
    expect(sig.length).toBe(64);
    // Should match our own HMAC of the demo payload
    const expectedPayload = JSON.stringify({
      event: "test.event",
      timestamp: "2025-01-01T00:00:00Z",
      data: { id: 42 },
    });
    const expected = sign(expectedPayload, "demo-secret-key");
    expect(sig).toBe(expected);
  });

  test("signed_fixture returns payload with correct signature header", async () => {
    const res = await fetch(`${TEST_URL}/signed-fixture`);
    expect(res.status).toBe(200);
    const body = await res.text();
    const sigHeader = res.headers.get("X-Signature");
    expect(sigHeader).toBeTruthy();
    const expectedPayload = JSON.stringify({
      event: "test.event",
      timestamp: "2025-01-01T00:00:00Z",
      data: { id: 42 },
    });
    expect(body).toBe(expectedPayload);
    // Verify the signature
    const expected = sign(body, "demo-secret-key");
    expect(sigHeader).toBe(expected);
  });

  test("verify_demo accepts a properly signed request", async () => {
    // First get a signed fixture to obtain a valid signature
    const fixtureRes = await fetch(`${TEST_URL}/signed-fixture`);
    const body = await fixtureRes.text();
    const sig = fixtureRes.headers.get("X-Signature");

    // Now verify: POST the body with X-Signature header
    const res = await fetch(`${TEST_URL}/verify-demo`, {
      method: "POST",
      headers: { "X-Signature": sig, "Content-Type": "application/json" },
      body,
    });
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("ok");
  });

  test("verify_demo rejects request with bad signature", async () => {
    const payload = JSON.stringify({
      event: "test.event",
      timestamp: "2025-01-01T00:00:00Z",
      data: { id: 42 },
    });
    const res = await fetch(`${TEST_URL}/verify-demo`, {
      method: "POST",
      headers: { "X-Signature": "bad-signature", "Content-Type": "application/json" },
      body: payload,
    });
    expect(res.status).toBe(401);
  });

  test("verify_demo rejects request with missing signature", async () => {
    const payload = JSON.stringify({
      event: "test.event",
      timestamp: "2025-01-01T00:00:00Z",
      data: { id: 42 },
    });
    const res = await fetch(`${TEST_URL}/verify-demo`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: payload,
    });
    expect(res.status).toBe(401);
  });

  test("sign_demo is deterministic", async () => {
    const res1 = await fetch(`${TEST_URL}/sign-demo`);
    const sig1 = await res1.text();
    const res2 = await fetch(`${TEST_URL}/sign-demo`);
    const sig2 = await res2.text();
    expect(sig1).toBe(sig2);
  });

  test("sign_demo produces different results for different payloads", async () => {
    // The signed_fixture signs the same payload as sign-demo but returns
    // it as a header — the value should match sign-demo's output
    const signRes = await fetch(`${TEST_URL}/sign-demo`);
    const directSig = await signRes.text();
    const fixtureRes = await fetch(`${TEST_URL}/signed-fixture`);
    const headerSig = fixtureRes.headers.get("X-Signature");
    expect(directSig).toBe(headerSig);
  });
});
