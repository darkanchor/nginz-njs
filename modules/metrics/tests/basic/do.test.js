import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "metrics";
const CONF = join(import.meta.dir, "nginx.conf");

describe("metrics — scaffold demo", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("describe returns stable metric summary", async () => {
    const res = await fetch(`${TEST_URL}/describe`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("requests_total type=c");
  });

  test("emit_demo returns stable statsd line", async () => {
    const res = await fetch(`${TEST_URL}/emit-demo`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("requests_total:1|c|#route:demo,status:200");
  });
});
