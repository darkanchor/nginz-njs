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

describe("feature_flags — session key resolution", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE, ["session"]);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("session-backed targeting resolves to the session subject", async () => {
    const startRes = await fetch(`${TEST_URL}/start?subject=alice`);
    expect(startRes.status).toBe(204);
    const cookie = startRes.headers.get("set-cookie");
    expect(cookie).not.toBeNull();

    const sessionBucket = await fetch(`${TEST_URL}/bucket/session`, {
      headers: { Cookie: cookie },
    }).then((res) => res.text());
    const userBucket = await fetch(`${TEST_URL}/bucket/user?id=alice`).then((res) =>
      res.text(),
    );

    expect(sessionBucket).toBe(userBucket);
  });

  test("missing session falls back to the request key path", async () => {
    const sessionBucket = await fetch(`${TEST_URL}/bucket/session`).then((res) =>
      res.text(),
    );
    const requestBucket = await fetch(`${TEST_URL}/bucket/request?id=fallback-42`).then((res) =>
      res.text(),
    );

    expect(sessionBucket).toBe(requestBucket);
  });

  test("missing session_dict falls back to the request key path", async () => {
    const sessionBucket = await fetch(`${TEST_URL}/bucket/session-no-dict`).then((res) =>
      res.text(),
    );
    const requestBucket = await fetch(`${TEST_URL}/bucket/request?id=fallback-42`).then((res) =>
      res.text(),
    );

    expect(sessionBucket).toBe(requestBucket);
  });

  test("expired session falls back to the request key path", async () => {
    const startRes = await fetch(`${TEST_URL}/start-short?subject=alice`);
    expect(startRes.status).toBe(204);
    const cookie = startRes.headers.get("set-cookie");
    expect(cookie).not.toBeNull();

    await Bun.sleep(1100);

    const sessionBucket = await fetch(`${TEST_URL}/bucket/session`, {
      headers: { Cookie: cookie },
    }).then((res) => res.text());
    const requestBucket = await fetch(`${TEST_URL}/bucket/request?id=fallback-42`).then((res) =>
      res.text(),
    );

    expect(sessionBucket).toBe(requestBucket);
  });
});
