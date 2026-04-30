#!/usr/bin/env bun
// Usage:
//   bun scripts/deploy.js <module> <dest>
//
// Copies dist/<module>/njs/app.js to <dest>/njs/app.js and prints the nginx
// config snippet needed to load the module. Warns if the nginx binary is
// missing any native modules declared under [metadata.native] in gleam.toml.
//
// Example:
//   bun scripts/deploy.js authz /etc/nginx/conf.d/authz

import { existsSync, mkdirSync, copyFileSync, readdirSync } from "fs";
import { join, resolve } from "path";
import { readMetadata, checkNativeDeps } from "./metadata.js";

const ROOT = import.meta.dir.replace(/\/scripts$/, "");
const MODULES_DIR = join(ROOT, "modules");
const DIST_DIR = join(ROOT, "dist");

function listModules() {
  return readdirSync(MODULES_DIR, { withFileTypes: true })
    .filter((d) => d.isDirectory())
    .map((d) => d.name);
}

const [dirName, rawDest] = process.argv.slice(2);

if (!dirName || !rawDest) {
  console.error(`Usage: bun scripts/deploy.js <module> <dest>`);
  console.error(`\nAvailable modules: ${listModules().join(", ")}`);
  console.error(`\nExample:\n  bun scripts/deploy.js authz /etc/nginx/conf.d/authz`);
  process.exit(1);
}

const moduleDir = join(MODULES_DIR, dirName);
if (!existsSync(moduleDir)) {
  console.error(`Module not found: ${dirName}`);
  console.error(`Available: ${listModules().join(", ")}`);
  process.exit(1);
}

const srcJs = join(DIST_DIR, dirName, "njs", "app.js");
if (!existsSync(srcJs)) {
  console.error(`dist/${dirName}/njs/app.js not found — run: bun scripts/build.js ${dirName}`);
  process.exit(1);
}

const meta = readMetadata(moduleDir);

const dest = resolve(rawDest);
const destNjs = join(dest, "njs");
mkdirSync(destNjs, { recursive: true });
copyFileSync(srcJs, join(destNjs, "app.js"));

// Warn (don't fail) at deploy time — the target nginx may be a separate host
checkNativeDeps(meta.native, { mode: "warn" });

const nativeList = Object.entries(meta.native)
  .flatMap(([src, mods]) => mods.map((m) => `${src}/${m}`));

console.log(`✓ Deployed ${meta.name} v${meta.version} to ${dest}/njs/app.js`);
if (nativeList.length > 0) {
  console.log(`  Requires native nginx modules: ${nativeList.join(", ")}`);
}

console.log(`
── nginx config snippet ──────────────────────────────────────────
# In your http {} block:
js_engine qjs;
js_path "${dest}/njs/";
js_import main from app.js;

# In your server {} / location {} blocks, use the handlers exposed
# by this module. See dist/${dirName}/nginx.conf for a working example.
──────────────────────────────────────────────────────────────────`);
