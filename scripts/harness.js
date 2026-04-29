import { spawn, spawnSync } from "bun";
import { mkdirSync, rmSync, existsSync } from "fs";
import { join, isAbsolute } from "path";

let nginxProcess = null;

const ROOT = import.meta.dir.replace(/\/scripts$/, "");
const NGINX_BIN = join(ROOT, "submodules/nginx/objs/nginx");
const TEST_PORT = 8888;

export function ensureBuild(moduleName) {
  const args = moduleName ? [moduleName] : [];
  const result = spawnSync(["bun", "scripts/build.js", ...args], {
    cwd: ROOT,
    stdout: "inherit",
    stderr: "inherit",
  });
  if (result.exitCode !== 0) throw new Error("build failed");
}

function preparePrefix(moduleName) {
  // Use dist/<name>/ as prefix so js_path "njs/" resolves to dist/<name>/njs/
  const prefix = join(ROOT, "dist", moduleName);
  const logsDir = join(prefix, "logs");
  if (existsSync(logsDir)) rmSync(logsDir, { recursive: true });
  mkdirSync(logsDir, { recursive: true });
  return prefix;
}

export async function startNginx(configPath, moduleName) {
  const prefix = preparePrefix(moduleName);
  const absConfig = isAbsolute(configPath)
    ? configPath
    : join(ROOT, configPath);

  nginxProcess = spawn([NGINX_BIN, "-c", absConfig, "-p", prefix], {
    stdout: "inherit",
    stderr: "inherit",
    cwd: ROOT,
  });

  await waitForPort(TEST_PORT);
  return prefix;
}

export async function stopNginx() {
  if (nginxProcess) {
    nginxProcess.kill("SIGQUIT");
    await nginxProcess.exited;
    nginxProcess = null;
  }
}

async function waitForPort(port, timeout = 5000) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    try {
      const ctrl = new AbortController();
      const id = setTimeout(() => ctrl.abort(), 100);
      await fetch(`http://localhost:${port}/`, { signal: ctrl.signal });
      clearTimeout(id);
      return;
    } catch {
      await Bun.sleep(50);
    }
  }
  throw new Error(`timeout waiting for port ${port}`);
}

export function cleanupRuntime(moduleName) {
  if (process.env.KEEP_LOGS) return;
  const runtimeDir = join(ROOT, "dist", moduleName, "runtime");
  if (existsSync(runtimeDir)) rmSync(runtimeDir, { recursive: true });
}

export const TEST_PORT_NUM = TEST_PORT;
export const TEST_URL = `http://localhost:${TEST_PORT}`;
