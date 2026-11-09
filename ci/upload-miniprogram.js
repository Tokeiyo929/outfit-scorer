"use strict";

// Upload the MyFood WeChat miniprogram via miniprogram-ci.
// Usage: node upload-miniprogram.js --private-key-path <path> [--version x.y.z] [--robot N] [--desc text]

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith("--")) throw new Error(`Unknown argument: ${key}`);
    const value = argv[i + 1];
    result[key.slice(2)] = value && !value.startsWith("--") ? value : "";
    i += 1;
  }
  return result;
}

function gitCommit() {
  try { return execSync("git rev-parse --short HEAD", { encoding: "utf8" }).trim(); }
  catch (_) { return "nogit"; }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const projectPath = path.resolve(__dirname, "..", "miniprogram");
  const config = JSON.parse(fs.readFileSync(path.join(projectPath, "project.config.json"), "utf8"));
  const appid = config.appid;
  const keyArg = args["private-key-path"] || "";
  const privateKeyPath = keyArg ? path.resolve(keyArg) : "";
  if (!appid) throw new Error("appid missing in miniprogram/project.config.json");
  if (!privateKeyPath || !fs.existsSync(privateKeyPath) || !fs.statSync(privateKeyPath).isFile()) {
    throw new Error("WeChat upload private key not found. Download it from mp.weixin.qq.com (开发管理-开发设置-小程序代码上传) and pass --private-key-path");
  }

  let ci;
  try { ci = require("miniprogram-ci"); }
  catch (_) {
    try {
      const { createRequire } = require("module");
      const globalRoot = execSync("npm root -g", { encoding: "utf8" }).trim();
      ci = createRequire(path.join(globalRoot, "noop.js"))("miniprogram-ci");
    } catch (_) {
      throw new Error("Cannot load miniprogram-ci. Run: npm install -g miniprogram-ci");
    }
  }

  const version = args.version || "1.0." + Date.now();
  const robot = Number(args.robot || "1");
  if (!Number.isInteger(robot) || robot < 1 || robot > 30) throw new Error("robot must be 1-30");
  const desc = args.desc || ("MyFood auto upload " + gitCommit());

  const project = new ci.Project({
    appid,
    type: "miniProgram",
    projectPath,
    privateKeyPath,
    ignores: ["node_modules/**/*"],
  });

  console.log(`UPLOAD_START appid=${appid} version=${version} robot=${robot} commit=${gitCommit()}`);
  const result = await ci.upload({
    project,
    version,
    desc,
    robot,
    setting: { es6: true, es7: true, minify: true, autoPrefixWXSS: true },
    onProgressUpdate: (p) => console.log(typeof p === "string" ? p : JSON.stringify(p)),
  });
  console.log(`UPLOAD_RESULT ${JSON.stringify(result || {})}`);
  console.log("UPLOAD_SUCCESS");
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
