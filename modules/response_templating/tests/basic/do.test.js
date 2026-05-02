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

  test("describe returns stable template summary", async () => {
    const res = await fetch(`${TEST_URL}/describe`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("demo placeholders=2");
  });

  test("render returns demo response", async () => {
    const res = await fetch(`${TEST_URL}/render`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("Hello Kaiwu — mode=demo");
  });

  test("from-request renders request-backed values", async () => {
    const res = await fetch(`${TEST_URL}/from-request?name=Alice&mode=preview`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("Hello Alice — mode=preview");
  });
});
