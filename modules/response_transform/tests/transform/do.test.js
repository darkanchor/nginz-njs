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

describe("response_transform — body filter", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("masks email field", async () => {
    const res = await fetch(`${TEST_URL}/transform`);
    expect(res.status).toBe(200);
    const body = JSON.parse(await res.text());
    expect(body["user.email"]).toBe("***");
  });

  test("drops trace field", async () => {
    const res = await fetch(`${TEST_URL}/transform`);
    const body = JSON.parse(await res.text());
    expect(body["internal.trace"]).toBeUndefined();
  });

  test("renames user.id to user_id", async () => {
    const res = await fetch(`${TEST_URL}/transform`);
    const body = JSON.parse(await res.text());
    expect(body["user_id"]).toBe("user42");
    expect(body["user.id"]).toBeUndefined();
  });

  test("preserves untransformed fields", async () => {
    const res = await fetch(`${TEST_URL}/transform`);
    const body = JSON.parse(await res.text());
    expect(body["keep"]).toBe("this");
  });
});
