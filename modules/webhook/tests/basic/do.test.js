import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "webhook";
const CONF = join(import.meta.dir, "nginx.conf");

describe("webhook — scaffold demo", () => {
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
      "demo_outbound_webhook algorithm=hmac-sha256 mode=outbound signature_header=X-Signature",
    );
  });

  test("describe_inbound returns stable summary", async () => {
    const res = await fetch(`${TEST_URL}/describe-inbound`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "demo_inbound_webhook algorithm=hmac-sha256 mode=inbound signature_header=X-Signature",
    );
  });
});
