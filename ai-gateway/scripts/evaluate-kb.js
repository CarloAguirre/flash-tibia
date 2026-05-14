import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { findKnowledgeMatches, loadKnowledgeBase } from '../kb.js';
import { findRecommendations } from '../recommender.js';

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const gatewayDirectory = path.resolve(scriptDirectory, '..');
const kbDirectory = process.env.KB_DIRECTORY
  ? path.resolve(process.env.KB_DIRECTORY)
  : path.join(gatewayDirectory, 'kb');
const goldenPath = process.env.KB_GOLDEN_FILE
  ? path.resolve(process.env.KB_GOLDEN_FILE)
  : path.join(kbDirectory, 'evals', 'golden.json');

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function describeTop(match) {
  return match ? `${match.id} (${match.kind}, score=${match.score})` : '<no match>';
}

function evaluateCase(knowledgeBase, testCase) {
  const matches = testCase.mode === 'recommendation'
    ? findRecommendations(knowledgeBase, testCase.text, testCase.context || {}, 3)
    : findKnowledgeMatches(knowledgeBase, testCase.text, testCase.context || {}, 3);
  const top = matches[0];

  if (testCase.expectedNoMatch) {
    return {
      ok: matches.length === 0,
      top,
      matches,
      message: matches.length === 0 ? 'expected no match' : `expected no match, got ${describeTop(top)}`,
    };
  }

  if (!top) {
    return { ok: false, top, matches, message: `expected ${testCase.expectedTopId}, got no match` };
  }

  if (testCase.expectedTopId && top.id !== testCase.expectedTopId) {
    return { ok: false, top, matches, message: `expected top ${testCase.expectedTopId}, got ${describeTop(top)}` };
  }

  if (testCase.expectedKind && top.kind !== testCase.expectedKind) {
    return { ok: false, top, matches, message: `expected kind ${testCase.expectedKind}, got ${top.kind}` };
  }

  return { ok: true, top, matches, message: `matched ${describeTop(top)}` };
}

let knowledgeBase;
let golden;
try {
  knowledgeBase = loadKnowledgeBase(kbDirectory);
  golden = readJson(goldenPath);
} catch (error) {
  console.error(`KB evaluation failed while loading inputs: ${error.message}`);
  process.exit(1);
}

if (golden.version !== knowledgeBase.version) {
  console.error(`KB evaluation failed: golden version ${golden.version || '<missing>'} does not match KB ${knowledgeBase.version}.`);
  process.exit(1);
}

if (!Array.isArray(golden.cases) || golden.cases.length === 0) {
  console.error('KB evaluation failed: golden cases must be a non-empty array.');
  process.exit(1);
}

const failures = [];
for (const testCase of golden.cases) {
  const result = evaluateCase(knowledgeBase, testCase);
  if (!result.ok) {
    failures.push({ testCase, result });
  }
}

if (failures.length > 0) {
  console.error(`KB evaluation failed: ${failures.length}/${golden.cases.length} cases failed.`);
  for (const failure of failures) {
    console.error(`- ${failure.testCase.id}: ${failure.result.message}`);
    const matches = failure.result.matches.map((match) => describeTop(match)).join(', ');
    console.error(`  matches: ${matches || '<none>'}`);
  }
  process.exit(1);
}

console.log(`KB evaluation OK: ${golden.cases.length}/${golden.cases.length} golden cases passed.`);