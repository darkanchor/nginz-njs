import { spawnSync } from "bun";
import { existsSync, copyFileSync, readdirSync, appendFileSync } from "fs";
import { join } from "path";
import { readMetadata, checkNativeDeps } from "./metadata.js";

const ROOT = import.meta.dir.replace(/\/scripts$/, "");
const MODULES_DIR = join(ROOT, "modules");
const DIST_DIR = join(ROOT, "dist");

function getModules(filter) {
  const all = readdirSync(MODULES_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name);
  return filter ? all.filter((n) => n === filter) : all;
}

async function buildModule(dirName) {
  const moduleDir = join(MODULES_DIR, dirName);
  const distDir = join(DIST_DIR, dirName);
  const meta = readMetadata(moduleDir);
  const pkgName = meta.name;

  checkNativeDeps(meta.native);

  console.log(`building ${dirName} (${pkgName})...`);

  const gleam = spawnSync(["gleam", "build", "--target", "javascript"], {
    cwd: moduleDir,
    stdout: "inherit",
    stderr: "inherit",
  });
  if (gleam.exitCode !== 0) throw new Error(`gleam build failed for ${dirName}`);

  const entry = join(moduleDir, `build/dev/javascript/${pkgName}/${pkgName}.mjs`);
  if (!existsSync(entry)) throw new Error(`entry not found: ${entry}`);

  const result = await Bun.build({
    entrypoints: [entry],
    outdir: join(distDir, "njs"),
    naming: "app.js",
    format: "esm",
    target: "browser",
    minify: false,
  });

  if (!result.success) {
    for (const msg of result.logs) console.error(msg);
    throw new Error(`bundle failed for ${dirName}`);
  }

  // njs loads the module via js_import which expects a default export
  appendFileSync(join(distDir, "njs", "app.js"), "\nexport default exports()\n");

  const conf = join(moduleDir, "nginx.conf");
  if (existsSync(conf)) copyFileSync(conf, join(distDir, "nginx.conf"));

  console.log(`  ✓ dist/${dirName}/njs/app.js`);
}

const filter = process.argv[2];
const modules = getModules(filter);

if (modules.length === 0) {
  console.error(filter ? `module not found: ${filter}` : "no modules found");
  process.exit(1);
}

for (const dirName of modules) {
  await buildModule(dirName);
}
