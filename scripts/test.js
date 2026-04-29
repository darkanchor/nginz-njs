import { spawnSync } from "bun";
import { readdirSync } from "fs";
import { join } from "path";

// Runs gleam unit tests (pure logic, no nginx needed) for all modules or one.
// Usage: bun scripts/test.js [module-name]

const ROOT = import.meta.dir.replace(/\/scripts$/, "");
const MODULES_DIR = join(ROOT, "modules");

function getModules(filter) {
  const all = readdirSync(MODULES_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name);
  return filter ? all.filter((n) => n === filter) : all;
}

function testModule(name) {
  console.log(`\ntesting ${name}...`);
  const result = spawnSync(["gleam", "test", "--target", "javascript"], {
    cwd: join(MODULES_DIR, name),
    stdout: "inherit",
    stderr: "inherit",
  });
  if (result.exitCode !== 0) {
    console.error(`  ✗ ${name} unit tests failed`);
    return false;
  }
  return true;
}

const filter = process.argv[2];
const modules = getModules(filter);

if (modules.length === 0) {
  console.error(filter ? `module not found: ${filter}` : "no modules found");
  process.exit(1);
}

let allPassed = true;
for (const name of modules) {
  if (!testModule(name)) allPassed = false;
}

process.exit(allPassed ? 0 : 1);
