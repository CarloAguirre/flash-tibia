import fs from 'node:fs';
import path from 'node:path';

const KB_FILES = {
  serverRules: 'server_rules.json',
  locations: 'locations.json',
  npcs: 'npcs.json',
  hunts: 'hunts.json',
  routes: 'routes.json',
  recommendationRules: 'recommendation_rules.json',
};

export const KNOWLEDGE_BASE_FILES = Object.freeze({ ...KB_FILES });

const STOP_WORDS = new Set([
  'a', 'an', 'and', 'are', 'can', 'como', 'con', 'de', 'del', 'do', 'donde', 'el', 'en', 'for', 'how', 'i', 'is', 'la',
  'las', 'los', 'me', 'mi', 'of', 'para', 'por', 'que', 'the', 'to', 'un', 'una', 'where', 'you', 'your', 'yo'
]);

const KIND_PRIORITY = {
  npc: 4,
  hunt: 3,
  location: 2,
  server_rule: 1,
  route: 0,
};

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function assertArray(value, label) {
  if (!Array.isArray(value) || value.length === 0) {
    throw new Error(`KB ${label} must be a non-empty array.`);
  }
}

function assertEntry(entry, label) {
  if (!entry || typeof entry !== 'object') {
    throw new Error(`KB ${label} entry must be an object.`);
  }
  if (!entry.id || typeof entry.id !== 'string') {
    throw new Error(`KB ${label} entry is missing id.`);
  }
  if (!entry.summary || typeof entry.summary !== 'string') {
    throw new Error(`KB ${label} entry ${entry.id} is missing summary.`);
  }
  assertArray(entry.keywords, `${label}.${entry.id}.keywords`);
}

export function validateKnowledgeBase(files) {
  assertArray(files.serverRules.rules, 'server_rules.rules');
  assertArray(files.locations.locations, 'locations.locations');
  assertArray(files.npcs.npcs, 'npcs.npcs');
  assertArray(files.hunts.hunts, 'hunts.hunts');
  assertArray(files.routes.routes, 'routes.routes');
  assertArray(files.recommendationRules.rules, 'recommendation_rules.rules');

  for (const rule of files.serverRules.rules) assertEntry(rule, 'server_rules');
  for (const location of files.locations.locations) assertEntry(location, 'locations');
  for (const npc of files.npcs.npcs) assertEntry(npc, 'npcs');
  for (const hunt of files.hunts.hunts) assertEntry(hunt, 'hunts');
  for (const route of files.routes.routes) assertEntry(route, 'routes');
  for (const rule of files.recommendationRules.rules) assertEntry(rule, 'recommendation_rules');

  const seenIds = new Set();
  for (const entry of [...buildEntries(files), ...files.recommendationRules.rules]) {
    if (seenIds.has(entry.id)) {
      throw new Error(`KB duplicate id: ${entry.id}.`);
    }
    seenIds.add(entry.id);
  }

  return true;
}

function normalize(value) {
  return String(value ?? '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
}

function tokenize(value) {
  return normalize(value)
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length > 1 && !STOP_WORDS.has(token));
}

function searchableText(entry) {
  return normalize([
    entry.id,
    entry.name,
    entry.title,
    entry.role,
    entry.area,
    entry.summary,
    ...(entry.creatures || []),
    ...(entry.keywords || []),
  ].filter(Boolean).join(' '));
}

function buildEntries(files) {
  return [
    ...files.serverRules.rules.map((entry) => ({ kind: 'server_rule', ...entry })),
    ...files.locations.locations.map((entry) => ({ kind: 'location', ...entry })),
    ...files.npcs.npcs.map((entry) => ({ kind: 'npc', ...entry })),
    ...files.hunts.hunts.map((entry) => ({ kind: 'hunt', ...entry })),
    ...files.routes.routes.map((entry) => ({ kind: 'route', ...entry })),
  ];
}

export function loadKnowledgeBase(directory) {
  const files = Object.fromEntries(
    Object.entries(KB_FILES).map(([key, fileName]) => [key, readJson(path.join(directory, fileName))])
  );

  validateKnowledgeBase(files);
  const entries = buildEntries(files);
  return {
    directory,
    version: files.serverRules.version || 'unknown',
    files,
    entries,
    recommendationRules: files.recommendationRules.rules.map((entry) => ({ kind: 'recommendation', ...entry })),
  };
}

function scoreLevelRange(entry, level) {
  if (entry.kind !== 'hunt' || !entry.levelRange || !Number.isFinite(level)) {
    return 0;
  }

  if (level >= entry.levelRange.min && level <= entry.levelRange.max) {
    return 4;
  }

  const distance = Math.min(Math.abs(level - entry.levelRange.min), Math.abs(level - entry.levelRange.max));
  return distance <= 3 ? 2 : 0;
}

export function findKnowledgeMatches(knowledgeBase, text, context = {}, maxMatches = 3) {
  const tokens = tokenize(text);
  const normalizedText = normalize(text);
  const playerLevel = Number(context?.player?.level);
  const hasHuntIntent = /hunt|hunting|level|levelear|cazar|exp|experience/.test(normalizedText);
  const hasNpcIntent = /npc|merchant|trade|buy|sell|comprar|vender|potion|rune|food|mail|what does|who is|que hace|quien es/.test(normalizedText);
  const hasLocationIntent = /tell me about|where is|city|town|location|ubicacion|ciudad|pueblo/.test(normalizedText);
  const hasRouteIntent = /route|ruta|path|camino|where|donde/.test(normalizedText);

  const scored = knowledgeBase.entries.map((entry) => {
    const haystack = searchableText(entry);
    const haystackTokens = new Set(tokenize(haystack));
    let score = 0;
    let textScore = 0;

    for (const token of tokens) {
      if (haystackTokens.has(token)) textScore += 2;
    }

    for (const keyword of entry.keywords || []) {
      const normalizedKeyword = normalize(keyword);
      if (normalizedKeyword && normalizedText.includes(normalizedKeyword)) textScore += 5;
    }

    if (entry.kind === 'route' && !hasRouteIntent) {
      return { entry, score: 0 };
    }

    score += textScore;

    if (entry.kind === 'hunt' && hasHuntIntent) {
      score += 2 + scoreLevelRange(entry, playerLevel);
    }
    if (entry.kind === 'npc' && hasNpcIntent && textScore > 0) score += 2;
    if (entry.kind === 'location' && hasLocationIntent && textScore > 0) score += 2;
    if (entry.kind === 'route' && hasRouteIntent && textScore > 0) score += 1;

    return { entry, score };
  });

  return scored
    .filter((candidate) => candidate.score > 0)
    .sort((left, right) => (
      right.score - left.score
      || (KIND_PRIORITY[right.entry.kind] ?? 0) - (KIND_PRIORITY[left.entry.kind] ?? 0)
      || left.entry.id.localeCompare(right.entry.id)
    ))
    .slice(0, maxMatches)
    .map((candidate) => ({ ...candidate.entry, score: candidate.score }));
}

export function knowledgeSummary(knowledgeBase) {
  return {
    version: knowledgeBase.version,
    entries: knowledgeBase.entries.length,
    recommendationRules: knowledgeBase.recommendationRules.length,
    files: Object.values(KB_FILES),
  };
}