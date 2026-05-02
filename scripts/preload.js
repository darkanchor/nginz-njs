import { ensureBuild } from "./harness.js";

// Preload always builds all modules to ensure dist/ is populated before
// Bun discovers and runs test files. The skip logic in ensureBuild avoids
// rebuilding when dist/ already exists.
ensureBuild(null);
