import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { KNOWLEDGE_BASE_FILES, knowledgeSummary, loadKnowledgeBase } from '../kb.js';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const gatewayDirectory = path.resolve(scriptDirectory, '..');
const repoRoot = path.resolve(gatewayDirectory, '..');
const kbDirectory = process.env.KB_DIRECTORY
  ? path.resolve(process.env.KB_DIRECTORY)
  : path.join(gatewayDirectory, 'kb');

const failures = [];
const warnings = [];

function fail(message) {
  failures.push(message);
}

function sourceList(entry, fallbackSource = []) {
  if (Array.isArray(entry.source) && entry.source.length > 0) {
    return entry.source;
  }
  return Array.isArray(fallbackSource) ? fallbackSource : [];
}

function validateSources(label, entries, fallbackSource = []) {
  for (const entry of entries) {
    const sources = sourceList(entry, fallbackSource);
    if (sources.length === 0) {
      fail(`${label}.${entry.id} has no source references.`);
      continue;
    }

    for (const source of sources) {
      if (typeof source !== 'string' || source.trim() === '') {
        fail(`${label}.${entry.id} has an invalid source reference.`);
        continue;
      }

      if (/^https?:\/\//i.test(source)) {
        continue;
      }

      const sourcePath = path.resolve(repoRoot, source);
      if (!fs.existsSync(sourcePath)) {
        fail(`${label}.${entry.id} source does not exist: ${source}`);
      }
    }
  }
}

function validateVersions(files, expectedVersion) {
  for (const [key, fileName] of Object.entries(KNOWLEDGE_BASE_FILES)) {
    const fileVersion = files[key]?.version;
    if (fileVersion !== expectedVersion) {
      fail(`${fileName} version ${fileVersion || '<missing>'} does not match ${expectedVersion}.`);
    }
  }
}

function validateKeywordShape(entries) {
  for (const entry of entries) {
    const uniqueKeywords = new Set(entry.keywords.map((keyword) => String(keyword).toLowerCase()));
    if (uniqueKeywords.size !== entry.keywords.length) {
      fail(`${entry.id} has duplicate keywords.`);
    }
  }
}

let knowledgeBase;
try {
  knowledgeBase = loadKnowledgeBase(kbDirectory);
} catch (error) {
  console.error(`KB validation failed while loading ${kbDirectory}: ${error.message}`);
  process.exit(1);
}

validateVersions(knowledgeBase.files, knowledgeBase.version);
validateKeywordShape([...knowledgeBase.entries, ...knowledgeBase.recommendationRules]);
validateSources('server_rules', knowledgeBase.files.serverRules.rules, knowledgeBase.files.serverRules.source);
validateSources('locations', knowledgeBase.files.locations.locations);
validateSources('npcs', knowledgeBase.files.npcs.npcs);
validateSources('hunts', knowledgeBase.files.hunts.hunts);
validateSources('routes', knowledgeBase.files.routes.routes);
validateSources('recommendation_rules', knowledgeBase.files.recommendationRules.rules);

if (!fs.existsSync(path.join(repoRoot, 'canary-main'))) {
  warnings.push('Repo source checks ran outside the full workspace; some source references may be unavailable here.');
}

if (failures.length > 0) {
  console.error('KB validation failed:');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

const summary = knowledgeSummary(knowledgeBase);
console.log(`KB validation OK: ${summary.version} (${summary.entries} entries, ${summary.files.length} files).`);
for (const warning of warnings) {
  console.warn(`Warning: ${warning}`);
}