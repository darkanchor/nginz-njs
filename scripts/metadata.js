import { readFileSync, existsSync } from "fs";
import { join } from "path";
import { spawnSync } from "bun";

const ROOT = import.meta.dir.replace(/\/scripts$/, "");
export const NGINX_BIN =
  process.env.NGINX_BIN ?? join(ROOT, "submodules/nginx/objs/nginx");

function tomlString(toml, key) {
  const m = toml.match(new RegExp(`^${key}\\s*=\\s*"([^"]+)"`, "m"));
  return m ? m[1] : null;
}

// Parse [metadata.native] section into { source: [module, ...], ... }
function parseNative(toml) {
  const section = toml.match(/\[metadata\.native\]([\s\S]*?)(?=\n\[|$)/)?.[1];
  if (!section) return {};
  const result = {};
  for (const line of section.split("\n")) {
    const m = line.match(/^(\w+)\s*=\s*\[([^\]]*)\]/);
    if (!m) continue;
    result[m[1]] = m[2].match(/"([^"]+)"/g)?.map((s) => s.replace(/"/g, "")) ?? [];
  }
  return result;
}

export function readMetadata(moduleDir) {
  const toml = readFileSync(join(moduleDir, "gleam.toml"), "utf8");
  return {
    name: tomlString(toml, "name"),
    version: tomlString(toml, "version"),
    description: tomlString(toml, "description"),
    native: parseNative(toml),
  };
}

// Check that every declared native dependency is present in the nginx binary.
// mode "fail" (default): throws on missing — used at build time.
// mode "warn": prints to stderr and continues — used at deploy time.
export function checkNativeDeps(native, { mode = "fail" } = {}) {
  const allModules = Object.values(native).flat();
  if (allModules.length === 0) return;

  if (!existsSync(NGINX_BIN)) {
    const msg = `nginx binary not found at ${NGINX_BIN} — run: make`;
    if (mode === "warn") { console.warn(`WARN: ${msg}`); return; }
    throw new Error(msg);
  }

  const result = spawnSync([NGINX_BIN, "-V"], { stderr: "pipe" });
  const args = result.stderr?.toString().match(/configure arguments:(.*)/)?.[1] ?? "";

  const missing = [];
  for (const [source, modules] of Object.entries(native)) {
    if (source !== "nginz") {
      console.warn(`WARN: unknown native source '${source}' — cannot verify automatically`);
      continue;
    }
    for (const m of modules) {
      if (!args.includes(`/modules/${m}`)) missing.push(m);
    }
  }

  if (missing.length === 0) return;

  const msg = [
    `Native module(s) required by this module are missing from the nginx binary:`,
    ...missing.map((m) => `  nginz/${m}`),
    `  Run: make NGINZ_MODULES="${missing.join(" ")}"`,
  ].join("\n");

  if (mode === "warn") { console.warn(`\nWARN: ${msg}\n`); return; }
  throw new Error(msg);
}
