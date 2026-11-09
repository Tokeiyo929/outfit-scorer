#!/usr/bin/env node
'use strict';

const Fs = require('fs');
const Path = require('path');

function readArg(name, fallback) {
  const index = process.argv.indexOf(name);
  if (index < 0 || index + 1 >= process.argv.length) return fallback || '';
  return process.argv[index + 1];
}

function normalizePath(value) {
  return String(value || '').replace(/\\/g, '/').replace(/\/+/g, '/').replace(/^\.\//, '');
}

function resolveTargetAssetPath(projectRoot, assetPath) {
  let normalized = normalizePath(assetPath || 'Load/Logo.png');
  if (!normalized.toLowerCase().startsWith('assets/')) {
    normalized = 'assets/' + normalized;
  }
  return Path.resolve(projectRoot, normalized);
}

function listFiles(rootPath, output) {
  output = output || [];
  if (!Fs.existsSync(rootPath)) return output;
  const entries = Fs.readdirSync(rootPath, { withFileTypes: true });
  for (const entry of entries) {
    const fullPath = Path.join(rootPath, entry.name);
    if (entry.isDirectory()) {
      listFiles(fullPath, output);
    } else {
      output.push(fullPath);
    }
  }
  return output;
}

function fileSize(filePath) {
  return Fs.statSync(filePath).size;
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

const projectRoot = Path.resolve(readArg('--project', process.cwd()));
const buildDir = Path.resolve(readArg('--build-dir', ''));
const logoPath = Path.resolve(readArg('--logo', ''));
const targetAssetPath = readArg('--target-asset', 'Load/Logo.png');

if (!Fs.existsSync(buildDir) || !Fs.statSync(buildDir).isDirectory()) {
  fail('Build directory not found: ' + buildDir);
}
if (!Fs.existsSync(logoPath) || !Fs.statSync(logoPath).isFile()) {
  fail('Logo file not found: ' + logoPath);
}

const targetFullPath = resolveTargetAssetPath(projectRoot, targetAssetPath);
const metaPath = targetFullPath + '.meta';
if (!Fs.existsSync(metaPath)) {
  fail('Target asset meta not found: ' + metaPath);
}

let meta = null;
try {
  meta = JSON.parse(Fs.readFileSync(metaPath, 'utf8'));
} catch (error) {
  fail('Target asset meta is not valid JSON: ' + metaPath);
}

const uuid = String(meta.uuid || '').toLowerCase();
if (!uuid) {
  fail('Target asset meta has no uuid: ' + metaPath);
}

const compactUuid = uuid.replace(/-/g, '');
const targetExt = Path.extname(targetFullPath).toLowerCase();
const logoExt = Path.extname(logoPath).toLowerCase();
if (targetExt && logoExt && targetExt !== logoExt) {
  fail('Logo extension must match target asset extension. target=' + targetExt + ' logo=' + logoExt);
}

const candidates = listFiles(buildDir).filter(function (filePath) {
  const ext = Path.extname(filePath).toLowerCase();
  if (targetExt && ext !== targetExt) return false;
  const name = Path.basename(filePath).toLowerCase();
  return name.indexOf(uuid) >= 0 || name.indexOf(compactUuid) >= 0;
});

if (candidates.length === 0) {
  fail('No output image matched target uuid. uuid=' + uuid + ' buildDir=' + buildDir);
}
if (candidates.length > 1) {
  fail('Multiple output images matched target uuid: ' + candidates.join(', '));
}

const outputPath = candidates[0];
const beforeBytes = fileSize(outputPath);
const logoBytes = fileSize(logoPath);
Fs.copyFileSync(logoPath, outputPath);

console.log(JSON.stringify({
  status: 'SUCCESS',
  targetAssetPath: normalizePath(Path.relative(projectRoot, targetFullPath)),
  targetUuid: uuid,
  sourceLogoPath: normalizePath(logoPath),
  outputPath: normalizePath(outputPath),
  beforeBytes: beforeBytes,
  afterBytes: logoBytes,
}, null, 2));
