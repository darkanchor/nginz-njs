import { ensureBuild } from "./harness.js";

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

ensureBuild(modulesFromArgv());
