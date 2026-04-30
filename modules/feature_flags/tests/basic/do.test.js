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

describe("feature_flags — flag evaluation", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("fully enabled flag returns 1", async () => {
    const res = await fetch(`${TEST_URL}/flag/on?id=user-abc`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("1");
  });

  test("fully disabled flag returns 0", async () => {
    const res = await fetch(`${TEST_URL}/flag/off?id=user-abc`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("0");
  });

  test("bucket is stable across requests for the same id", async () => {
    const r1 = await fetch(`${TEST_URL}/bucket?id=stable-user`);
    const r2 = await fetch(`${TEST_URL}/bucket?id=stable-user`);
    const b1 = await r1.text();
    const b2 = await r2.text();
    expect(b1).toBe(b2);
  });

  test("bucket is in range 0-99", async () => {
    const res = await fetch(`${TEST_URL}/bucket?id=range-test`);
    const b = parseInt(await res.text(), 10);
    expect(b).toBeGreaterThanOrEqual(0);
    expect(b).toBeLessThan(100);
  });

  test("different ids produce different buckets", async () => {
    const r1 = await fetch(`${TEST_URL}/bucket?id=user-1`);
    const r2 = await fetch(`${TEST_URL}/bucket?id=user-2`);
    const b1 = parseInt(await r1.text(), 10);
    const b2 = parseInt(await r2.text(), 10);
    expect(b1).toBe(24);
    expect(b2).toBe(48);
  });

  test("force-on override beats disabled flag", async () => {
    const res = await fetch(`${TEST_URL}/flag/force-on?id=any`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("1");
  });

  test("force-off override beats enabled flag", async () => {
    const res = await fetch(`${TEST_URL}/flag/force-off?id=any`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("0");
  });

  test("variant flag returns a variant name (A, B, or C)", async () => {
    const res = await fetch(`${TEST_URL}/flag/variant?id=any`);
    expect(res.status).toBe(200);
    const v = await res.text();
    expect(["A", "B", "C"].includes(v)).toBe(true);
  });

  test("variant force-on overrides disabled flag", async () => {
    const res = await fetch(`${TEST_URL}/flag/variant-force-on?id=any`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("A");
  });

  test("variant is stable across requests for the same id", async () => {
    const r1 = await fetch(`${TEST_URL}/flag/variant?id=stable`);
    const r2 = await fetch(`${TEST_URL}/flag/variant?id=stable`);
    expect(await r1.text()).toBe(await r2.text());
  });

  test("describe returns decision metadata for boolean flag", async () => {
    const res = await fetch(`${TEST_URL}/flag/describe?id=u`);
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toMatch(/^flag=test bucket=\d+ result=1$/);
  });

  test("describe_variant returns decision metadata for variant flag", async () => {
    const res = await fetch(`${TEST_URL}/flag/describe-variant?id=u`);
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toMatch(/^flag=exp bucket=\d+ variant=B fallback=0$/);
  });
});
