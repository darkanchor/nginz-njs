import { spawnSync } from "bun";
import { readdirSync } from "fs";
import { join } from "path";

const ROOT = import.meta.dir.replace(/\/scripts$/, "");
const MODULES_DIR = join(ROOT, "modules");

const modules = readdirSync(MODULES_DIR, { withFileTypes: true })
  .filter((d) => d.isDirectory())
  .map((d) => d.name);

for (const name of modules) {
  spawnSync(["gleam", "format", "src", "test"], {
    cwd: join(MODULES_DIR, name),
    stdout: "inherit",
    stderr: "inherit",
  });
}
