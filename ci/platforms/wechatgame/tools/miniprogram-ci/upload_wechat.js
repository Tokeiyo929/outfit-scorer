"use strict";

const fs = require("fs");
const path = require("path");
const { createRequire } = require("module");
const { execSync } = require("child_process");

function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 1) {
    const key = argv[i];
    if (!key.startsWith("--")) {
      throw new Error(`Unknown argument: ${key}`);
    }
    const name = key.slice(2);
    const value = argv[i + 1];
    if (!value || value.startsWith("--")) {
      throw new Error(`Missing value for argument: ${key}`);
    }
    result[name] = value;
    i += 1;
  }
  return result;
}

function requireArg(args, name) {
  if (!args[name]) {
    throw new Error(`Missing argument: --${name}`);
  }
  return args[name];
}

function requireMiniprogramCi() {
  try {
    return require("miniprogram-ci");
  } catch (_) {
    try {
      const globalRoot = execSync("npm root -g", { encoding: "utf8" }).trim();
      const globalRequire = createRequire(path.join(globalRoot, "noop.js"));
      return globalRequire("miniprogram-ci");
    } catch (_) {
      throw new Error("Cannot load miniprogram-ci. Run: npm install -g miniprogram-ci");
    }
  }
}

function assertExists(label, targetPath) {
  if (!targetPath || !fs.existsSync(targetPath)) {
    throw new Error(`${label} not found: ${targetPath}`);
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const appid = requireArg(args, "appid");
  const projectPath = path.resolve(requireArg(args, "project-path"));
  const privateKeyPath = path.resolve(requireArg(args, "private-key-path"));
  const version = requireArg(args, "version");
  const desc = args.desc || version;
  const robot = Number(requireArg(args, "robot"));

  if (!Number.isInteger(robot) || robot < 1 || robot > 30) {
    throw new Error(`robot must be between 1 and 30. Current value: ${args.robot}`);
  }

  assertExists("WeChat build directory", projectPath);
  assertExists("WeChat private key", privateKeyPath);

  const ci = requireMiniprogramCi();
  const project = new ci.Project({
    appid,
    type: "miniGame",
    projectPath,
    privateKeyPath,
    ignores: ["node_modules/**/*"],
  });

  console.log(`WECHAT_UPLOAD_START appid=${appid} version=${version} robot=${robot}`);
  const result = await ci.upload({
    project,
    version,
    desc,
    robot,
    setting: {
      es6: true,
      es7: true,
      minify: true,
      autoPrefixWXSS: true,
    },
    onProgressUpdate: (progress) => {
      if (typeof progress === "string") {
        console.log(`WECHAT_PROGRESS ${progress}`);
      } else {
        console.log(`WECHAT_PROGRESS ${JSON.stringify(progress)}`);
      }
    },
  });

  console.log(`WECHAT_UPLOAD_RESULT ${JSON.stringify(result || {})}`);
  console.log("WECHAT_UPLOAD_SUCCESS");
}

main().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
