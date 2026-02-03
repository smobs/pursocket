// Browser bundle smoke test script.
// Bundles PurSocket.BrowserTest with esbuild for browser platform.
// Exits 0 on success, 1 on failure.

import { buildSync } from "esbuild";
import { statSync } from "fs";

try {
  buildSync({
    entryPoints: ["output/PurSocket.BrowserTest/index.js"],
    bundle: true,
    outfile: "dist/PurSocket.bundle.js",
    format: "esm",
    platform: "browser",
    logLevel: "info",
  });

  const stats = statSync("dist/PurSocket.bundle.js");
  if (stats.size === 0) {
    console.error("ERROR: Bundle file is empty");
    process.exit(1);
  }

  console.log(`Browser bundle created: dist/PurSocket.bundle.js (${stats.size} bytes)`);
  console.log("Browser bundle smoke test PASSED");
} catch (err) {
  console.error("Browser bundle smoke test FAILED:", err.message);
  process.exit(1);
}
