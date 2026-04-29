import { describe, test, expect, beforeAll, afterAll } from "bun:test";
import { join } from "path";
import {
  startNginx,
  stopNginx,
  cleanupRuntime,
  TEST_URL,
} from "../../../../scripts/harness.js";

const MODULE = "workflow";
const CONF = join(import.meta.dir, "nginx.conf");

describe("workflow — chain subrequest", () => {
  beforeAll(async () => {
    await startNginx(CONF, MODULE);
  });

  afterAll(async () => {
    await stopNginx();
    cleanupRuntime(MODULE);
  });

  test("chains through internal upstream and returns its body", async () => {
    const res = await fetch(`${TEST_URL}/chain`);
    expect(res.status).toBe(200);
    const body = await res.text();
    expect(body).toBe("upstream-response");
  });
});
