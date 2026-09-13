const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const repoRoot = path.resolve(__dirname, '..');
const sourceRoot = path.join(repoRoot, 'otclient');
const args = process.argv.slice(2);
const replaceAll = args.includes('--replace-all');
const replacePrefixes = args
  .filter((arg) => arg.startsWith('--replace-prefix='))
  .map((arg) => arg.slice('--replace-prefix='.length));
const addFiles = args
  .filter((arg) => arg.startsWith('--add-file='))
  .map((arg) => arg.slice('--add-file='.length));
const targetDirs = args
  .filter((arg) => arg !== '--replace-all' && !arg.startsWith('--replace-prefix=') && !arg.startsWith('--add-file='))
  .map((arg) => path.resolve(repoRoot, arg));

if (replacePrefixes.length === 0) {
  replacePrefixes.push('/modules/game_ai_copilot/');
}

if (targetDirs.length === 0) {
  targetDirs.push(path.join(repoRoot, 'web15', 'public'));
}

const metadataPattern = /loadPackage\(\{files:\[(.*?)\],remote_package_size:(\d+),package_uuid:"(sha256-[0-9a-f]+)"\}\)/s;
const filePattern = /\{filename:"((?:\\.|[^"\\])*)",start:(\d+),end:(\d+)\}/g;
const generatedDirsPattern = /\n\s*\/\/ BEGIN repack-otclient-preload generated directories\n[\s\S]*?\/\/ END repack-otclient-preload generated directories\n/;
const runWithFsPattern = /((?:async\s+)?function\s+runWithFS\s*\([^)]*\)\s*\{)/;

function decodeJsString(value) {
  return JSON.parse(`"${value}"`);
}

function normalizePreloadFilename(filename) {
  const normalized = filename.replace(/\\/g, '/');
  return normalized.startsWith('/') ? normalized : `/${normalized}`;
}

function sourcePathFor(filename) {
  return path.join(sourceRoot, normalizePreloadFilename(filename).replace(/^\/+/, '').split('/').join(path.sep));
}

function shouldReplace(filename) {
  return replaceAll || replacePrefixes.some((prefix) => filename.startsWith(prefix));
}

function parseMetadata(jsText, jsPath) {
  const metadataMatch = jsText.match(metadataPattern);
  if (!metadataMatch) {
    throw new Error(`Could not find preload metadata in ${jsPath}`);
  }

  const entries = [];
  for (const match of metadataMatch[1].matchAll(filePattern)) {
    entries.push({
      filename: decodeJsString(match[1]),
      start: Number(match[2]),
      end: Number(match[3])
    });
  }

  return {
    original: metadataMatch[0],
    remotePackageSize: Number(metadataMatch[2]),
    entries
  };
}

function buildPreloadDirectoryCalls(filenames) {
  const calls = [];
  const seen = new Set();

  for (const requestedFile of filenames) {
    const normalized = normalizePreloadFilename(requestedFile);
    const parts = normalized.replace(/^\/+/, '').split('/');
    let parent = '/';

    for (let index = 0; index < parts.length - 1; index += 1) {
      const name = parts[index];
      const key = `${parent}\0${name}`;
      if (!seen.has(key)) {
        seen.add(key);
        calls.push(`  Module['FS_createPath'](${JSON.stringify(parent)}, ${JSON.stringify(name)}, true, true);`);
      }
      parent = parent === '/' ? `/${name}` : `${parent}/${name}`;
    }
  }

  return calls;
}

function ensurePreloadDirectories(jsText, filenames, jsPath) {
  const calls = buildPreloadDirectoryCalls(filenames);
  if (calls.length === 0) {
    return jsText;
  }

  const block = `\n  // BEGIN repack-otclient-preload generated directories\n${calls.join('\n')}\n  // END repack-otclient-preload generated directories\n`;
  if (generatedDirsPattern.test(jsText)) {
    return jsText.replace(generatedDirsPattern, block);
  }

  if (!runWithFsPattern.test(jsText)) {
    throw new Error(`Could not find runWithFS in ${jsPath}; cannot safely add preload directories`);
  }

  return jsText.replace(runWithFsPattern, `$1${block}`);
}

function repack(targetDir) {
  const jsPath = path.join(targetDir, 'otclient.js');
  const dataPath = path.join(targetDir, 'otclient.data');
  const jsText = fs.readFileSync(jsPath, 'utf8');
  const oldData = fs.readFileSync(dataPath);
  const metadata = parseMetadata(jsText, jsPath);

  if (metadata.remotePackageSize !== oldData.length) {
    throw new Error(`${dataPath} size does not match otclient.js metadata`);
  }

  let offset = 0;
  let replaced = 0;
  let added = 0;
  const chunks = [];
  const knownFiles = new Set();

  const entries = metadata.entries.map((entry) => {
    knownFiles.add(entry.filename);
    const sourcePath = sourcePathFor(entry.filename);
    const useSource = shouldReplace(entry.filename) && fs.existsSync(sourcePath) && fs.statSync(sourcePath).isFile();
    const content = useSource ? fs.readFileSync(sourcePath) : oldData.subarray(entry.start, entry.end);
    if (useSource) {
      replaced += 1;
    }

    const nextEntry = { filename: entry.filename, start: offset, end: offset + content.length };
    offset = nextEntry.end;
    chunks.push(content);
    return nextEntry;
  });

  for (const requestedFile of addFiles) {
    const filename = normalizePreloadFilename(requestedFile);
    if (knownFiles.has(filename)) {
      continue;
    }

    const sourcePath = sourcePathFor(filename);
    if (!fs.existsSync(sourcePath) || !fs.statSync(sourcePath).isFile()) {
      throw new Error(`Cannot add missing preload source file: ${sourcePath}`);
    }

    const content = fs.readFileSync(sourcePath);
    entries.push({ filename, start: offset, end: offset + content.length });
    offset += content.length;
    chunks.push(content);
    knownFiles.add(filename);
    added += 1;
  }

  const newData = Buffer.concat(chunks, offset);
  const packageUuid = `sha256-${crypto.createHash('sha256').update(newData).digest('hex')}`;
  const filesText = entries
    .map((entry) => `{filename:${JSON.stringify(entry.filename)},start:${entry.start},end:${entry.end}}`)
    .join(',');
  const newMetadata = `loadPackage({files:[${filesText}],remote_package_size:${newData.length},package_uuid:"${packageUuid}"})`;

  let newJsText = jsText.replace(metadata.original, newMetadata);
  newJsText = ensurePreloadDirectories(newJsText, addFiles, jsPath);

  fs.writeFileSync(dataPath, newData);
  fs.writeFileSync(jsPath, newJsText);

  console.log(`${path.relative(repoRoot, targetDir)} replaced=${replaced} added=${added} size=${oldData.length}->${newData.length} uuid=${packageUuid}`);
}

for (const targetDir of targetDirs) {
  repack(targetDir);
}
