import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "response_transform";
const CONF = join(import.meta.dir, "nginx.conf");

describe("response_transform — scaffold demo", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("describe returns stable plan summary", async () => {
    const res = await fetch(`${TEST_URL}/describe`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "default_response_transform [mask:user.email, drop:internal.trace, rename:user.id->user_id]",
    );
  });

  test("preview_plan returns stable preview text", async () => {
    const res = await fetch(`${TEST_URL}/preview-plan`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "preview: default_response_transform [mask:user.email, drop:internal.trace, rename:user.id->user_id]",
    );
  });
});
