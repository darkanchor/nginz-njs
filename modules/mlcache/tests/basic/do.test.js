import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "mlcache";
const CONF = join(import.meta.dir, "nginx.conf");

describe("mlcache — scaffold demo", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("describe returns stable cache summary", async () => {
    const res = await fetch(`${TEST_URL}/describe`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("shared_dict policy=refresh_on_miss ttl=60");
  });

  test("blocked returns explicit shared_dict blocker", async () => {
    const res = await fetch(`${TEST_URL}/blocked`);
    expect(res.status).toBe(501);
    expect(await res.text()).toBe(
      "mlcache runtime blocked until native shared_dict backing is available",
    );
  });
});
