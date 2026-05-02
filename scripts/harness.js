import { spawn, spawnSync } from "bun";
import { mkdirSync, rmSync, existsSync, copyFileSync, readdirSync } from "fs";
import { join, isAbsolute } from "path";

let nginxProcess = null;

const ROOT = import.meta.dir.replace(/\/scripts$/, "");
const NGINX_BIN = join(ROOT, "submodules/nginx/objs/nginx");
const TEST_PORT = 8888;

export function ensureBuild(moduleNames) {
  // moduleNames is null (build all) or string[] (build specific modules)
  if (moduleNames && moduleNames.length > 0) {
    // Selective: only invoke build.js for modules whose bundle is missing.
    // build.js accepts exactly one module name, so call it once per module.
    const missing = moduleNames.filter(
      (name) => !existsSync(join(ROOT, "dist", name, "njs", "app.js"))
    );
    for (const name of missing) {
      const r = spawnSync(["bun", "scripts/build.js", name], {
        cwd: ROOT,
        stdout: "inherit",
        stderr: "inherit",
      });
      if (r.exitCode !== 0) throw new Error(`build failed for ${name}`);
    }
  } else {
    // All: skip only when every known module already has a bundle.
    const distDir = join(ROOT, "dist");
    const modulesDir = join(ROOT, "modules");
    if (existsSync(distDir) && existsSync(modulesDir)) {
      const allBuilt = readdirSync(modulesDir).every((name) =>
        existsSync(join(distDir, name, "njs", "app.js"))
      );
      if (allBuilt) return;
    }
    const r = spawnSync(["bun", "scripts/build.js"], {
      cwd: ROOT,
      stdout: "inherit",
      stderr: "inherit",
    });
    if (r.exitCode !== 0) throw new Error("build failed");
  }
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

// Kill any leftover nginx from a previous crashed/interrupted test run.
function killOrphans() {
  const result = spawnSync(["pgrep", "-f", NGINX_BIN], { stdout: "pipe" });
  const pids = result.stdout?.toString().trim();
  if (!pids) return;
  for (const pid of pids.split("\n")) {
    spawnSync(["kill", "-TERM", pid]);
  }
}

export async function startNginx(configPath, moduleName, extraModules = []) {
  killOrphans();

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

  // Verify the spawned process is still alive — a stale nginx on the port
  // would let waitForPort succeed while our new process died from EADDRINUSE.
  if (nginxProcess.exitCode !== null) {
    throw new Error(
      `nginx exited with code ${nginxProcess.exitCode} — port ${TEST_PORT} may be in use by another process`,
    );
  }

  return prefix;
}

export async function stopNginx() {
  if (nginxProcess) {
    // SIGTERM triggers fast shutdown; SIGQUIT is graceful and waits for
    // workers to drain connections, which can exceed Bun's default 5s hook timeout.
    nginxProcess.kill("SIGTERM");
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
