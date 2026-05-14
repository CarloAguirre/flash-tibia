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
const targetDirs = args
  .filter((arg) => arg !== '--replace-all' && !arg.startsWith('--replace-prefix='))
  .map((arg) => path.resolve(repoRoot, arg));

if (replacePrefixes.length === 0) {
  replacePrefixes.push('/modules/game_ai_copilot/');
}

if (targetDirs.length === 0) {
  targetDirs.push(path.join(repoRoot, 'web15', 'public'));
}

const metadataPattern = /loadPackage\(\{files:\[(.*?)\],remote_package_size:(\d+),package_uuid:"(sha256-[0-9a-f]+)"\}\)/s;
const filePattern = /\{filename:"((?:\\.|[^"\\])*)",start:(\d+),end:(\d+)\}/g;

function decodeJsString(value) {
  return JSON.parse(`"${value}"`);
}

function sourcePathFor(filename) {
  return path.join(sourceRoot, filename.replace(/^\/+/, '').split('/').join(path.sep));
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
  const chunks = [];
  const entries = metadata.entries.map((entry) => {
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

  const newData = Buffer.concat(chunks, offset);
  const packageUuid = `sha256-${crypto.createHash('sha256').update(newData).digest('hex')}`;
  const filesText = entries
    .map((entry) => `{filename:${JSON.stringify(entry.filename)},start:${entry.start},end:${entry.end}}`)
    .join(',');
  const newMetadata = `loadPackage({files:[${filesText}],remote_package_size:${newData.length},package_uuid:"${packageUuid}"})`;

  fs.writeFileSync(dataPath, newData);
  fs.writeFileSync(jsPath, jsText.replace(metadata.original, newMetadata));

  console.log(`${path.relative(repoRoot, targetDir)} replaced=${replaced} size=${oldData.length}->${newData.length} uuid=${packageUuid}`);
}

for (const targetDir of targetDirs) {
  repack(targetDir);
}