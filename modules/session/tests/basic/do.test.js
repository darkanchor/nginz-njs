import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "session";
const CONF = join(import.meta.dir, "nginx.conf");

describe("session — scaffold demo", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("describe returns stable session summary", async () => {
    const res = await fetch(`${TEST_URL}/describe`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("sid backend=shared_dict ttl=3600 same_site=Lax");
  });
});
