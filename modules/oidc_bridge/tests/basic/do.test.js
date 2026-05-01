import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "oidc_bridge";
const CONF = join(import.meta.dir, "nginx.conf");

describe("oidc_bridge — basic", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("bind session with full identity", async () => {
    const res = await fetch(`${TEST_URL}/oidc/full`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.subject).toBe("user-42");
    expect(body.email).toBe("alice@example.test");
    expect(body.name).toBe("Alice");
    expect(body.session_id).toMatch(/^oidc:user-42:/);
  });

  test("bind session with minimal identity", async () => {
    const res = await fetch(`${TEST_URL}/oidc/minimal`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.subject).toBe("user-99");
    expect(body.email).toBe("");
    expect(body.name).toBe("");
  });

  test("map claims to authz dict", async () => {
    const res = await fetch(`${TEST_URL}/oidc/map`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.sub).toBe("user-42");
    expect(body.email).toBe("alice@example.test");
    expect(body.name).toBe("Alice");
  });

  test("resolve feature flag key", async () => {
    const res = await fetch(`${TEST_URL}/oidc/flag`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.flag_key).toBe("ByUserId:user-42");
  });

  test("missing OIDC claims returns defaults", async () => {
    const res = await fetch(`${TEST_URL}/oidc/missing`);
    expect(res.status).toBe(200);
    const body = await res.json();
    expect(body.subject).toBe("unknown");
  });
});
