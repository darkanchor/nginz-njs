import { spawnSync } from "bun";
import { readdirSync, existsSync } from "fs";
import { join } from "path";
import { ensureBuild } from "./harness.js";

const ROOT = import.meta.dir.replace(/\/scripts$/, "");
const MODULES_DIR = join(ROOT, "modules");

// Extract module names from the test-file paths in argv.
// e.g. "modules/workflow/tests/circuit/do.test.js" → "workflow"
// Returns null when no specific module paths are found → build all.
function modulesFromArgv() {
  const names = new Set();
  for (const arg of process.argv) {
    const m = arg.match(/(?:^|\/)modules\/([^/]+)\//);
    if (m) names.add(m[1]);
  }
  return names.size > 0 ? [...names] : null;
}

// Run gleam build for each module so that build/ artifacts (including ngs)
// are always present when bun discovers *_test.mjs files during broad test runs.
function ensureGleamBuilds(moduleNames) {
  const all = readdirSync(MODULES_DIR, { withFileTypes: true })
    .filter((e) => e.isDirectory())
    .map((e) => e.name);
  const targets = moduleNames ? all.filter((n) => moduleNames.includes(n)) : all;
  for (const name of targets) {
    const moduleDir = join(MODULES_DIR, name);
    if (!existsSync(join(moduleDir, "gleam.toml"))) continue;
    const r = spawnSync(["gleam", "build", "--target", "javascript"], {
      cwd: moduleDir,
      stdout: "pipe",
      stderr: "pipe",
    });
    if (r.exitCode !== 0) {
      process.stderr.write(r.stderr);
      throw new Error(`gleam build failed for ${name}`);
    }
  }
}

const modules = modulesFromArgv();
ensureGleamBuilds(modules);
ensureBuild(modules);
