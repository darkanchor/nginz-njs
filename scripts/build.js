import { spawnSync } from "bun";
import { existsSync, copyFileSync, readdirSync, appendFileSync, statSync } from "fs";
import { join } from "path";
import { readMetadata, checkNativeDeps } from "./metadata.js";

// Returns the mtime (ms) of the newest file under `dir`, recursively.
function newestMtime(dir) {
  let newest = 0;
  function walk(d) {
    for (const entry of readdirSync(d, { withFileTypes: true })) {
      const p = join(d, entry.name);
      if (entry.isDirectory()) walk(p);
      else newest = Math.max(newest, statSync(p).mtimeMs);
    }
  }
  if (existsSync(dir)) walk(dir);
  return newest;
}

// True when the bundle is newer than gleam.toml and every file in src/.
function isBundleFresh(moduleDir, distDir) {
  const bundle = join(distDir, "njs", "app.js");
  if (!existsSync(bundle)) return false;
  const bundleMtime = statSync(bundle).mtimeMs;
  if (statSync(join(moduleDir, "gleam.toml")).mtimeMs > bundleMtime) return false;
  return newestMtime(join(moduleDir, "src")) <= bundleMtime;
}

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

  if (isBundleFresh(moduleDir, distDir)) return;

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
    // njs (QuickJS) is its own runtime, NOT node and NOT a browser.
    // - target "browser" makes Bun inline broken polyfills: it swaps njs's
    //   native global `Buffer` for a node:buffer shim that THROWS at runtime,
    //   and replaces `import qs from 'querystring'` with a wrong browser
    //   polyfill. target "node" leaves Buffer as a global and emits njs
    //   builtins as bare specifiers (`querystring`, not `node:querystring`),
    //   which njs resolves to its own modules. This mirrors how the upstream
    //   `ngs` package configures esbuild.
    target: "node",
    // Mark njs builtin modules external so the bundler never tries to resolve
    // or polyfill them. Node-builtin names (crypto/fs/zlib/querystring/buffer)
    // are already external under target "node"; `xml` is njs-only and would
    // otherwise fail to resolve, so it must be listed explicitly. Keep this in
    // sync with `external` in ngs's src/ngs_ffi.mjs.
    external: ["querystring", "crypto", "fs", "xml", "zlib", "buffer"],
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
