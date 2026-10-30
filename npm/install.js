#!/usr/bin/env node
// Unpacks the bundled MouseCustomize.app into the given folder
// (default ~/Applications) and opens it.
const { execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

const zip = path.join(__dirname, "MouseCustomize.zip");
const appsDir = process.argv[2]
  ? path.resolve(process.argv[2])
  : path.join(os.homedir(), "Applications");
const app = path.join(appsDir, "MouseCustomize.app");

// Quit a running copy so it can be replaced.
try {
  execFileSync("pkill", ["-x", "MouseCustomize"]);
} catch {}

fs.mkdirSync(appsDir, { recursive: true });
fs.rmSync(app, { recursive: true, force: true });
execFileSync("ditto", ["-x", "-k", zip, appsDir]);

console.log(`Installed ${app}`);
execFileSync("open", [app]);
