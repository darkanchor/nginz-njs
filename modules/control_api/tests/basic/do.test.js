import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "control_api";
const CONF = join(import.meta.dir, "nginx.conf");

describe("control_api — runtime API", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("describe returns route inventory", async () => {
    const res = await fetch(`${TEST_URL}/runtime/describe`);
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toContain("GET /runtime/health");
    expect(body).toContain("GET /runtime/flag");
    expect(body).toContain("GET /runtime/cache/probe");
  });

  test("health returns JSON ok", async () => {
    const res = await fetch(`${TEST_URL}/runtime/health`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = JSON.parse(await res.text());
    expect(body.status).toBe("ok");
    expect(body.service).toBe("control_api");
  });

  test("system_info returns JSON runtime details", async () => {
    const res = await fetch(`${TEST_URL}/runtime/system`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = JSON.parse(await res.text());
    expect(body.status).toBe("ok");
    expect(body.module).toBe("control_api");
    expect(body.version).toBe("0.1.0");
    expect(Number(body.now_ms)).toBeGreaterThan(0);
  });

  test("inspect_flag returns error for unknown flag", async () => {
    const res = await fetch(`${TEST_URL}/runtime/flag?name=unknown_flag`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = JSON.parse(await res.text());
    expect(body.status).toBe("error");
    expect(body.message).toContain("unknown_flag");
  });

  test("inspect_flag requires name param", async () => {
    const res = await fetch(`${TEST_URL}/runtime/flag`);
    expect(res.status).toBe(400);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = JSON.parse(await res.text());
    expect(body.status).toBe("error");
  });

  test("toggle_flag writes flag and inspect_flag reads it back", async () => {
    const setRes = await fetch(
      `${TEST_URL}/runtime/flag/set?name=dark_mode&enabled=1&pct=50`,
    );
    expect(setRes.status).toBe(200);
    expect(setRes.headers.get("content-type")).toContain("application/json");
    const setBody = JSON.parse(await setRes.text());
    expect(setBody.status).toBe("ok");
    expect(setBody.action).toBe("set");
    expect(setBody.name).toBe("dark_mode");
    expect(setBody.enabled).toBe("true");
    expect(setBody.rollout_pct).toBe("50");

    const getRes = await fetch(`${TEST_URL}/runtime/flag?name=dark_mode`);
    expect(getRes.status).toBe(200);
    const getBody = JSON.parse(await getRes.text());
    expect(getBody.status).toBe("ok");
    expect(getBody.name).toBe("dark_mode");
    expect(getBody.enabled).toBe("true");
    expect(getBody.rollout_pct).toBe("50");
  });

  test("probe_cache reaches the configured shared dict", async () => {
    const res = await fetch(`${TEST_URL}/runtime/cache/probe?dict=feature_flags`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = JSON.parse(await res.text());
    expect(body.status).toBe("ok");
    expect(body.dict).toBe("feature_flags");
    expect(body.reachable).toBe("true");
  });

  test("probe_cache requires dict param", async () => {
    const res = await fetch(`${TEST_URL}/runtime/cache/probe`);
    expect(res.status).toBe(400);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = JSON.parse(await res.text());
    expect(body.status).toBe("error");
    expect(body.message).toContain("dict");
  });

  test("probe_session reaches the configured shared dict", async () => {
    const res = await fetch(`${TEST_URL}/runtime/session/probe?dict=sessions`);
    expect(res.status).toBe(200);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = JSON.parse(await res.text());
    expect(body.status).toBe("ok");
    expect(body.session_dict).toBe("sessions");
    expect(body.reachable).toBe("true");
  });

  test("probe_session rejects missing dict param", async () => {
    const res = await fetch(`${TEST_URL}/runtime/session/probe`);
    expect(res.status).toBe(400);
    expect(res.headers.get("content-type")).toContain("application/json");
    const body = JSON.parse(await res.text());
    expect(body.status).toBe("error");
    expect(body.message).toContain("dict");
  });
});
