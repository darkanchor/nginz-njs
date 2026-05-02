import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

// Requires nginx built with the native circuit-breaker module:
//   make NGINZ_MODULES="echoz circuit-breaker"

const MODULE = "workflow";
const CONF = join(import.meta.dir, "nginx.conf");

describe("workflow — circuit-aware resilience (native circuit-breaker)", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("reads closed state when circuit has not tripped", async () => {
    const res = await fetch(`${TEST_URL}/circuit/state`);
    expect(res.status).toBe(200);
    expect(await res.text()).toBe("closed");
  });

  test("circuit opens after failure threshold and returns 503", async () => {
    // Two failures trip the circuit (threshold=2).
    const r1 = await fetch(`${TEST_URL}/circuit/trip`);
    expect(r1.status).toBe(500);
    const r2 = await fetch(`${TEST_URL}/circuit/trip`);
    expect(r2.status).toBe(500);
    // Access handler now returns 503 before njs runs.
    const r3 = await fetch(`${TEST_URL}/circuit/trip`);
    expect(r3.status).toBe(503);
  });

  test("half-open probe: allow_probe_when_half_open runs step and recovers", async () => {
    // Trip /circuit/probe (separate circuit from /circuit/trip).
    const f1 = await fetch(`${TEST_URL}/circuit/probe?fail=1`);
    expect(f1.status).toBe(500);
    const f2 = await fetch(`${TEST_URL}/circuit/probe?fail=1`);
    expect(f2.status).toBe(500);
    // Circuit is now open; access handler returns 503.
    const open = await fetch(`${TEST_URL}/circuit/probe`);
    expect(open.status).toBe(503);

    // Wait for circuit_breaker_timeout (100 ms) → transitions to half_open.
    await new Promise((resolve) => setTimeout(resolve, 150));

    // Half-open: access handler passes through → njs runs → allow_probe_when_half_open
    // calls the healthy step → returns 200.
    const probe = await fetch(`${TEST_URL}/circuit/probe`);
    expect(probe.status).toBe(200);
    expect(await probe.text()).toBe("healthy");

    // success_threshold=1: one success closes the circuit.
    const closed = await fetch(`${TEST_URL}/circuit/probe`);
    expect(closed.status).toBe(200);
  });
});
