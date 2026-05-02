import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "feature_flags";
const CONF = join(import.meta.dir, "nginx.conf");

describe("feature_flags — canary-aware evaluation", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("canary header routes to ForceOn — flag returns 1 despite 0% rollout", async () => {
    const res = await fetch(`${TEST_URL}/flag/canary-header?id=user-1`, {
      headers: { "X-Canary": "true" },
    });
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("1");
  });

  test("without canary header NoOverride applies — flag returns 0 at 0% rollout", async () => {
    const res = await fetch(`${TEST_URL}/flag/canary-header?id=user-1`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("0");
  });

  test("100% canary percentage always routes to ForceOn", async () => {
    const res = await fetch(`${TEST_URL}/flag/canary-pct?id=user-2`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("1");
  });

  test("describe_canary annotates with canary=1 for canary requests", async () => {
    const res = await fetch(`${TEST_URL}/flag/describe-canary?id=user-3`, {
      headers: { "X-Canary": "true" },
    });
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toMatch(/^flag=beta bucket=\d+ result=1 canary=1$/);
  });

  test("describe_canary annotates with canary=0 for non-canary requests", async () => {
    const res = await fetch(`${TEST_URL}/flag/describe-canary?id=user-3`);
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toMatch(/^flag=beta bucket=\d+ result=0 canary=0$/);
  });
});
