import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "response_templating";
const CONF = join(import.meta.dir, "nginx.conf");

describe("response_templating — scaffold demo", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("describe returns registry summary", async () => {
    const res = await fetch(`${TEST_URL}/describe`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("registry count=2");
  });

  test("render returns demo response", async () => {
    const res = await fetch(`${TEST_URL}/render`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("Hello Kaiwu — mode=demo");
  });

  test("render-safe preserves missing placeholders", async () => {
    const res = await fetch(`${TEST_URL}/render-safe`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("Hello Kaiwu — mode={{mode}}");
  });

  test("from-request renders request-backed values", async () => {
    const res = await fetch(`${TEST_URL}/from-request?name=Alice&mode=preview`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("Hello Alice — mode=preview");
  });

  test("from-request falls back to guest and standard", async () => {
    const res = await fetch(`${TEST_URL}/from-request`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("Hello guest — mode=standard");
  });

  test("render-json returns application/json output", async () => {
    const res = await fetch(`${TEST_URL}/render-json?name=Alice&mode=preview`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = JSON.parse(await res.text());
    expect(body.greeting).toBe("Hello Alice");
    expect(body.mode).toBe("preview");
  });

  test("from-vars renders nginx variable bindings with placeholder defaults", async () => {
    const res = await fetch(`${TEST_URL}/from-vars`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("Hello Casey — mode=mode");
  });
});
