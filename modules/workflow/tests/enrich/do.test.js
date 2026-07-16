import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

// Requires nginx built with the native echoz module:
//   make   (the default NGINZ_MODULES includes echoz)

const MODULE = "workflow";
const CONF = join(import.meta.dir, "nginx.conf");

describe("workflow — enrich fan-out (native echoz backends)", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("fans out to auth and profile, combines both bodies", async () => {
    const res = await fetch(`${TEST_URL}/enrich`);
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toContain('{"ok":true}');
    expect(body).toContain('"name":"alice"');
  });

  test("response is a newline-joined combination of subrequest bodies", async () => {
    const res = await fetch(`${TEST_URL}/enrich`);
    const body = await res.text();
    const parts = body.split("\n");
    expect(parts.length).toBe(2);
    expect(JSON.parse(parts[0])).toEqual({ ok: true });
    expect(JSON.parse(parts[1])).toEqual({ name: "alice", id: 1 });
  });
});
