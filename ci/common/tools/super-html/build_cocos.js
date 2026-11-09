#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const CHANNEL_KEYS = [
  'common',
  'common_min',
  'applovin',
  'ironsource',
  'ironsource2025',
  'mintegral',
  'unity',
  'google',
  'google_portrait',
  'google_landscape',
  'facebook',
  'facebook_split_zip',
  'pangle',
  'pangle_portrait',
  'pangle_landscape',
  'liftoff',
  'moloco',
  'tiktok',
  'vungle',
  'bigo',
  'kwai',
  'nefta',
  'nefta_zip'
];

function printUsage() {
  console.log([
    'Usage:',
    '  node ci/common/tools/super-html/build_cocos.js --project <projectRoot> --input <webMobileBuildDir> [--output <superHtmlDir>] [--version <cocosVersion>]',
    '',
    'Options:',
    '  --project   Cocos project root. Defaults to current working directory.',
    '  --input     Cocos web-mobile build directory. Required.',
    '  --output    super-html output directory. Defaults to <input>/../super-html.',
    '  --version   Cocos Creator version. Defaults to project.json version or 2.4.11.',
    '  --help      Show this help.'
  ].join('\n'));
}

function parseArgs(argv) {
  const result = {
    project: process.cwd(),
    input: '',
    output: '',
    version: ''
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      result.help = true;
      continue;
    }

    if (!arg.startsWith('--')) {
      throw new Error(`Unexpected argument: ${arg}`);
    }

    const key = arg.slice(2);
    if (!Object.prototype.hasOwnProperty.call(result, key)) {
      throw new Error(`Unknown option: ${arg}`);
    }

    const value = argv[i + 1];
    if (!value || value.startsWith('--')) {
      throw new Error(`Missing value for ${arg}`);
    }

    result[key] = value;
    i += 1;
  }

  return result;
}

function readJsonIfExists(filePath) {
  if (!fs.existsSync(filePath)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function resolveVersion(projectRoot, explicitVersion) {
  if (explicitVersion) {
    return explicitVersion;
  }

  const projectJson = readJsonIfExists(path.join(projectRoot, 'project.json'));
  if (projectJson && projectJson.version) {
    return String(projectJson.version);
  }

  return '2.4.11';
}

function getChannelKey(adapter) {
  if (adapter.s_name === 'facebook' && adapter.b_out_zip && adapter.b_split_res) {
    return 'facebook_split_zip';
  }
  if (adapter.s_name === 'nefta' && adapter.b_out_zip) {
    return 'nefta_zip';
  }
  return adapter.s_config_name || adapter.s_name;
}

function applyEnabledChannels(buildModule, projectRoot) {
  const channelConfig = readJsonIfExists(path.join(projectRoot, 'settings', 'super-html-channels.json'));
  if (!channelConfig || !channelConfig.enabled_channels || typeof channelConfig.enabled_channels !== 'object') {
    return CHANNEL_KEYS;
  }

  const adapters = buildModule.config && buildModule.config.inject_channel_adapter;
  if (!Array.isArray(adapters)) {
    throw new Error('super-html build config does not expose inject_channel_adapter.');
  }

  const enabled = [];
  adapters.forEach((adapter) => {
    const key = getChannelKey(adapter);
    adapter.b_enable = channelConfig.enabled_channels[key] === true;
    if (adapter.b_enable) {
      enabled.push(key);
    }
  });

  return enabled;
}

function ensureEditorShim(projectRoot, version) {
  global.Editor = global.Editor || {};
  global.Editor.Project = global.Editor.Project || {};
  global.Editor.Project.path = projectRoot;
  global.Editor.projectPath = projectRoot;
  global.Editor.App = global.Editor.App || {};
  global.Editor.App.version = version;
  global.Editor.remote = global.Editor.remote || {};
  global.Editor.remote.App = global.Editor.remote.App || {};
  global.Editor.remote.App.version = version;
}

function collectHtmlFiles(outputDir) {
  if (!fs.existsSync(outputDir)) {
    return [];
  }

  const result = [];
  const pending = [outputDir];
  while (pending.length > 0) {
    const current = pending.pop();
    const entries = fs.readdirSync(current, { withFileTypes: true });
    entries.forEach((entry) => {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        pending.push(fullPath);
      } else if (entry.isFile() && path.extname(entry.name).toLowerCase() === '.html') {
        const stat = fs.statSync(fullPath);
        result.push({
          path: fullPath,
          sizeBytes: stat.size
        });
      }
    });
  }
  result.sort((a, b) => a.path.localeCompare(b.path));
  return result;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    printUsage();
    return;
  }

  const projectRoot = path.resolve(args.project);
  const inputDir = path.resolve(args.input || '');
  const outputDir = args.output ? path.resolve(args.output) : path.resolve(inputDir, '..', 'super-html');
  const superHtmlRoot = path.resolve(__dirname, 'vendor');

  if (!args.input) {
    throw new Error('--input is required.');
  }
  if (!fs.existsSync(projectRoot) || !fs.statSync(projectRoot).isDirectory()) {
    throw new Error(`Project root does not exist: ${projectRoot}`);
  }
  if (!fs.existsSync(inputDir) || !fs.statSync(inputDir).isDirectory()) {
    throw new Error(`Input build directory does not exist: ${inputDir}`);
  }
  if (!fs.existsSync(superHtmlRoot) || !fs.statSync(superHtmlRoot).isDirectory()) {
    throw new Error(`super-html vendor directory does not exist: ${superHtmlRoot}`);
  }

  const version = resolveVersion(projectRoot, args.version);
  ensureEditorShim(projectRoot, version);

  const buildModule = require(path.join(superHtmlRoot, 'dist', 'core', 'build'));
  const BuildClass = buildModule.default || buildModule;
  const enabledChannels = applyEnabledChannels(buildModule, projectRoot);

  if (!buildModule.config) {
    throw new Error('super-html build config is unavailable.');
  }
  buildModule.config.is_obfuscator = false;

  fs.rmSync(outputDir, { recursive: true, force: true });
  fs.mkdirSync(outputDir, { recursive: true });

  console.log(`[super-html] input=${inputDir}`);
  console.log(`[super-html] output=${outputDir}`);
  console.log(`[super-html] version=${version}`);
  console.log(`[super-html] obfuscator=${buildModule.config.is_obfuscator}`);
  console.log(`[super-html] channels=${enabledChannels.join(',') || '(none)'}`);

  const startedAt = Date.now();
  await new Promise((resolve, reject) => {
    let settled = false;
    function done(error) {
      if (settled) {
        return;
      }
      settled = true;
      if (error) {
        reject(error);
      } else {
        resolve();
      }
    }

    try {
      new BuildClass(version, inputDir, outputDir, done);
    } catch (error) {
      done(error);
    }
  });

  const htmlFiles = collectHtmlFiles(outputDir);
  const totalBytes = htmlFiles.reduce((sum, file) => sum + file.sizeBytes, 0);
  const summary = {
    status: 'SUCCESS',
    inputDir,
    outputDir,
    version,
    obfuscator: buildModule.config.is_obfuscator,
    channels: enabledChannels,
    htmlFiles,
    totalBytes,
    elapsedMs: Date.now() - startedAt
  };

  console.log(`[super-html] completed. files=${htmlFiles.length} totalBytes=${totalBytes}`);
  console.log(JSON.stringify(summary));
}

main().catch((error) => {
  console.error(`[super-html] failed: ${error && error.stack ? error.stack : error}`);
  process.exitCode = 1;
});
