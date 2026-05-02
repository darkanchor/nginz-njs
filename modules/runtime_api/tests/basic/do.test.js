import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "runtime_api";
const CONF = join(import.meta.dir, "nginx.conf");

describe("runtime_api — scaffold demo", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("describe returns stable route inventory", async () => {
    const res = await fetch(`${TEST_URL}/runtime/describe`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "GET /runtime/describe name=describe\nGET /runtime/health name=health\nGET /runtime/flag name=inspect_flag\nGET /runtime/flag/preview name=toggle_flag_preview",
    );
  });

  test("health returns ok runtime status", async () => {
    const res = await fetch(`${TEST_URL}/runtime/health`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("ok runtime_api=ready");
  });

  test("inspect_flag previews named flag", async () => {
    const res = await fetch(`${TEST_URL}/runtime/flag?name=dark_mode`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("ok flag=dark_mode mode=inspect");
  });

  test("toggle_flag_preview previews a write request", async () => {
    const res = await fetch(
      `${TEST_URL}/runtime/flag/preview?name=dark_mode&enabled=1`,
    );
    expect(res.status).toBe(200);
    expect(await res.text()).toBe(
      "ok preview=set_flag name=dark_mode enabled=1",
    );
  });
});
