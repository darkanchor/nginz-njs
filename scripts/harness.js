import { spawn, spawnSync } from "bun";
import { mkdirSync, rmSync, existsSync, copyFileSync } from "fs";
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

function deployBundle(prefix, moduleName, targetName = "app.js") {
  const source = join(ROOT, "dist", moduleName, "njs", "app.js");
  const target = join(prefix, "njs", targetName);
  copyFileSync(source, target);
}

function preparePrefix(moduleName) {
  // Use dist/<name>/ as prefix so js_path "njs/" resolves to dist/<name>/njs/
  const prefix = join(ROOT, "dist", moduleName);
  const logsDir = join(prefix, "logs");
  if (existsSync(logsDir)) rmSync(logsDir, { recursive: true });
  mkdirSync(logsDir, { recursive: true });
  return prefix;
}

export async function startNginx(configPath, moduleName, extraModules = []) {
  const prefix = preparePrefix(moduleName);
  const absConfig = isAbsolute(configPath)
    ? configPath
    : join(ROOT, configPath);

  for (const extraModule of extraModules) {
    deployBundle(prefix, extraModule, `${extraModule}.js`);
  }

  // Deploy the config into dist/<module>/ so js_path "njs/" resolves to dist/<module>/njs/
  const deployedConfig = join(prefix, "nginx.conf");
  copyFileSync(absConfig, deployedConfig);

  nginxProcess = spawn([NGINX_BIN, "-c", deployedConfig, "-p", prefix], {
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
  const logsDir = join(ROOT, "dist", moduleName, "logs");
  if (existsSync(logsDir)) rmSync(logsDir, { recursive: true });
}

export const TEST_PORT_NUM = TEST_PORT;
export const TEST_URL = `http://localhost:${TEST_PORT}`;
