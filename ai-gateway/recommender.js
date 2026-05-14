const STOP_WORDS = new Set([
  'a', 'an', 'and', 'are', 'at', 'can', 'do', 'for', 'i', 'is', 'me', 'my', 'of', 'the', 'to', 'what', 'where', 'you'
]);

function normalize(value) {
  return String(value ?? '').toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
}

function tokenize(value) {
  return normalize(value)
    .split(/[^a-z0-9]+/)
    .filter((token) => token.length > 1 && !STOP_WORDS.has(token));
}

function recommendationIntent(text) {
  return /recommend|suggest|what should|next|progress|proximo|siguiente|recomienda|deberia|que hago/.test(normalize(text));
}

function huntProgressIntent(text) {
  return /hunt|hunting|level|levelear|cazar|exp|experience/.test(normalize(text));
}

function scoreLevelRange(rule, level) {
  if (!rule.levelRange || !Number.isFinite(level)) {
    return 0;
  }

  if (level >= rule.levelRange.min && level <= rule.levelRange.max) {
    return 6;
  }

  const distance = Math.min(Math.abs(level - rule.levelRange.min), Math.abs(level - rule.levelRange.max));
  return distance <= 2 ? 2 : 0;
}

function scoreKeywords(rule, text) {
  const normalizedText = normalize(text);
  const textTokens = new Set(tokenize(text));
  let score = 0;

  for (const keyword of rule.keywords || []) {
    const normalizedKeyword = normalize(keyword);
    if (normalizedKeyword && normalizedText.includes(normalizedKeyword)) {
      score += 5;
      continue;
    }

    for (const token of tokenize(keyword)) {
      if (textTokens.has(token)) score += 1;
    }
  }

  return score;
}

export function findRecommendations(knowledgeBase, text, context = {}, maxRecommendations = 2) {
  const rules = knowledgeBase.recommendationRules || [];
  const playerLevel = Number(context?.player?.level);
  const hasRecommendationIntent = recommendationIntent(text);
  const hasProgressIntent = huntProgressIntent(text);

  if (!hasRecommendationIntent && !hasProgressIntent) {
    return [];
  }

  return rules
    .map((rule) => {
      const keywordScore = scoreKeywords(rule, text);
      const levelScore = scoreLevelRange(rule, playerLevel);
      const intentScore = hasRecommendationIntent ? 3 : 0;
      const priorityScore = Number(rule.priority || 0) / 100;
      const score = keywordScore + levelScore + intentScore + priorityScore;
      return { ...rule, score };
    })
    .filter((rule) => rule.score > 0)
    .sort((left, right) => right.score - left.score || right.priority - left.priority || left.id.localeCompare(right.id))
    .slice(0, maxRecommendations);
}