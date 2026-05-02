import { ensureBuild } from "./harness.js";

// Extract the module name from the test file path passed via CLI args.
// e.g., "bun test modules/authz/tests/jwt/do.test.js" → "authz"
// When running "bun run test" (no file), build everything.
function extractModuleName() {
  for (const arg of process.argv) {
    const m = arg.match(/modules\/([^/]+)\/tests?\//);
    if (m) return m[1];
  }
  return null;
}

ensureBuild(extractModuleName());
