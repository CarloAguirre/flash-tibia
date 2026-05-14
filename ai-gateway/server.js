import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { findKnowledgeMatches, knowledgeSummary, loadKnowledgeBase } from './kb.js';
import { findRecommendations } from './recommender.js';

const DEFAULT_PORT = 8095;
const DEFAULT_MAX_BODY_BYTES = 32768;
const DEFAULT_MAX_TEXT_BYTES = 240;
const MODULE_DIRECTORY = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_KB_DIRECTORY = path.join(MODULE_DIRECTORY, 'kb');

function parseBoolean(value, defaultValue = false) {
  if (value === undefined || value === null || value === '') {
    return defaultValue;
  }

  return ['1', 'true', 'yes', 'on'].includes(String(value).toLowerCase());
}

function readNumber(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

export function getGatewayConfig(env = process.env) {
  return {
    port: readNumber(env.PORT, DEFAULT_PORT),
    mode: String(env.AI_GATEWAY_MODE ?? 'mock').toLowerCase(),
    geminiEnabled: parseBoolean(env.GEMINI_ENABLED, false),
    maxBodyBytes: readNumber(env.MAX_BODY_BYTES, DEFAULT_MAX_BODY_BYTES),
    maxTextBytes: readNumber(env.MAX_TEXT_BYTES, DEFAULT_MAX_TEXT_BYTES),
    kbDirectory: env.KB_DIRECTORY || DEFAULT_KB_DIRECTORY,
  };
}

function sendJson(response, statusCode, payload) {
  const body = JSON.stringify(payload);
  response.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Cache-Control': 'no-store',
  });
  response.end(body);
}

function sendError(response, statusCode, code, message, requestId = '') {
  sendJson(response, statusCode, {
    v: 1,
    type: 'error',
    requestId,
    code,
    error: message,
  });
}

async function readJsonBody(request, maxBodyBytes) {
  const chunks = [];
  let totalBytes = 0;
  let tooLarge = false;

  for await (const chunk of request) {
    totalBytes += chunk.length;
    if (totalBytes > maxBodyBytes) {
      tooLarge = true;
      continue;
    }
    chunks.push(chunk);
  }

  if (tooLarge) {
    const error = new Error('payload too large');
    error.code = 'PAYLOAD_TOO_LARGE';
    throw error;
  }

  const body = Buffer.concat(chunks).toString('utf8');
  if (body.trim() === '') {
    const error = new Error('empty request body');
    error.code = 'INVALID_JSON';
    throw error;
  }

  try {
    return JSON.parse(body);
  } catch (parseError) {
    const error = new Error('invalid json');
    error.code = 'INVALID_JSON';
    throw error;
  }
}

function normalizedText(value) {
  return String(value ?? '').replace(/\s+/g, ' ').trim();
}

export function validateChatRequest(payload, config = getGatewayConfig()) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return { ok: false, status: 400, code: 'INVALID_REQUEST', message: 'Copilot request must be a JSON object.' };
  }

  if (payload.type !== 'chat') {
    return { ok: false, status: 400, code: 'UNSUPPORTED_TYPE', message: 'Only chat requests are supported by the gateway mock.' };
  }

  const text = normalizedText(payload.text);
  if (text === '') {
    return { ok: false, status: 400, code: 'EMPTY_TEXT', message: 'Write a message before sending it to Copilot.' };
  }

  if (Buffer.byteLength(text, 'utf8') > config.maxTextBytes) {
    return { ok: false, status: 400, code: 'TEXT_TOO_LONG', message: 'Copilot message is too long.' };
  }

  return { ok: true, text };
}

function responseSources(items) {
  return items.map((item) => ({
    id: item.id,
    kind: item.kind,
    title: item.name || item.title,
    source: item.source || [],
  }));
}

function responseCards(matches, recommendations = []) {
  const recommendationCards = recommendations.map((recommendation) => ({
    id: recommendation.id,
    type: recommendation.kind,
    title: recommendation.title,
    summary: recommendation.summary,
    reasons: recommendation.reasons || [],
    cautions: recommendation.cautions || [],
    related: recommendation.related || [],
    source: recommendation.source || [],
  }));

  const knowledgeCards = matches.map((match) => {
    const card = {
      id: match.id,
      type: match.kind,
      title: match.name || match.title,
      summary: match.summary,
      source: match.source || [],
    };

    if (match.kind === 'route') {
      card.status = match.status || 'documented-only';
      card.previewOnly = match.status === 'preview-only';
      card.waypointCount = Array.isArray(match.waypoints) ? match.waypoints.length : 0;
    }

    return card;
  });

  return [...recommendationCards, ...knowledgeCards];
}

function normalizeWaypoint(point) {
  if (!point || typeof point !== 'object') {
    return null;
  }

  const positionX = Number(point.x);
  const positionY = Number(point.y);
  const positionZ = Number(point.z);
  if (!Number.isFinite(positionX) || !Number.isFinite(positionY) || !Number.isFinite(positionZ)) {
    return null;
  }

  return {
    x: positionX,
    y: positionY,
    z: positionZ,
    label: typeof point.label === 'string' ? point.label : '',
  };
}

function responseRoute(matches) {
  const routeMatch = matches.find((match) => (
    match.kind === 'route'
    && match.status === 'preview-only'
    && Array.isArray(match.waypoints)
    && match.waypoints.length > 0
  ));

  if (!routeMatch) {
    return null;
  }

  const waypoints = routeMatch.waypoints.map(normalizeWaypoint).filter(Boolean);
  if (waypoints.length === 0) {
    return null;
  }

  return {
    id: routeMatch.id,
    title: routeMatch.name || routeMatch.title,
    status: 'preview-only',
    previewOnly: true,
    summary: routeMatch.summary,
    destination: normalizeWaypoint(routeMatch.destination) || waypoints[waypoints.length - 1],
    waypoints,
    source: routeMatch.source || [],
    actions: [],
    requiresConfirmation: false,
  };
}

function buildRecommendationMessage(context, recommendations) {
  const player = context.player && typeof context.player === 'object' ? context.player : {};
  const playerName = player.name || 'the player';
  const primary = recommendations[0];
  const cautionText = primary.cautions && primary.cautions.length > 0 ? ` Caution: ${primary.cautions[0]}` : '';
  return `Phase 3 deterministic recommender selected ${primary.title} for ${playerName}. ${primary.summary}${cautionText} This is read-only guidance; Gemini, routes, and tasker are still disabled.`;
}

function buildRouteMessage(context, route) {
  const player = context.player && typeof context.player === 'object' ? context.player : {};
  const playerName = player.name || 'the player';
  return `Phase 4 route preview selected ${route.title} for ${playerName}. I added read-only minimap waypoints when the client supports it. This does not move your character; Gemini, tasker, and actions are still disabled.`;
}

function buildKnowledgeMessage(text, context, matches) {
  const player = context.player && typeof context.player === 'object' ? context.player : {};
  const playerName = player.name || 'the player';
  const playerLevel = player.level || '?';

  if (matches.length === 0) {
    return `Phase 2 KB mock received your chat for ${playerName}. No tengo ese dato en la KB curada todavia. I can see your level is ${playerLevel}, but Gemini, routes, and tasker are still disabled.`;
  }

  const primary = matches[0];
  if (primary.kind === 'hunt') {
    const levelRange = primary.levelRange ? `level ${primary.levelRange.min}-${primary.levelRange.max}` : 'the listed level range';
    const creatures = (primary.creatures || []).join(', ');
    return `Phase 2 KB mock matched ${primary.name} for ${playerName} (${levelRange}). Creatures: ${creatures}. ${primary.summary} Gemini, routes, and tasker are still disabled.`;
  }

  if (primary.kind === 'npc') {
    return `Phase 2 KB mock matched NPC ${primary.name} for ${playerName}: ${primary.role}. ${primary.summary} Gemini, routes, and tasker are still disabled.`;
  }

  if (primary.kind === 'location') {
    return `Phase 2 KB mock matched ${primary.name} for ${playerName}. ${primary.summary} Gemini, routes, and tasker are still disabled.`;
  }

  if (primary.kind === 'route') {
    return `Phase 4 route preview matched ${primary.name} for ${playerName}. ${primary.summary} This is visual guidance only; autowalk, tasker, and actions are still disabled.`;
  }

  return `Phase 2 KB mock matched ${primary.title || primary.name} for ${playerName}. ${primary.summary} Gemini, routes, and tasker are still disabled.`;
}

export function buildGatewayResponse(payload, text, config = getGatewayConfig(), knowledgeBase = loadKnowledgeBase(config.kbDirectory)) {
  const context = payload.context && typeof payload.context === 'object' ? payload.context : {};
  const player = context.player && typeof context.player === 'object' ? context.player : {};
  const position = player.position && typeof player.position === 'object' ? player.position : {};
  const playerName = player.name || 'the player';
  const playerLevel = player.level || '?';
  const positionText = `${position.x ?? '?'},${position.y ?? '?'},${position.z ?? '?'}`;
  const matches = findKnowledgeMatches(knowledgeBase, text, context, 3);
  const recommendations = findRecommendations(knowledgeBase, text, context, 2);
  const route = responseRoute(matches);
  const sourceItems = [...recommendations, ...matches];

  return {
    v: 1,
    type: 'answer',
    requestId: payload.requestId || '',
    provider: 'mock',
    model: 'eldera-copilot-kb-mock-v1',
    message: route
      ? buildRouteMessage(context, route)
      : recommendations.length > 0
        ? buildRecommendationMessage(context, recommendations)
        : buildKnowledgeMessage(text, context, matches),
    echo: text,
    context,
    cards: responseCards(matches, recommendations),
    sources: responseSources(sourceItems),
    knowledge: {
      version: knowledgeBase.version,
      matched: matches.length,
      recommendations: recommendations.length,
    },
    recommender: {
      mode: 'deterministic',
      matched: recommendations.length,
    },
    route,
    actions: [],
    requiresConfirmation: false,
    gateway: {
      mode: config.mode,
      geminiEnabled: config.geminiEnabled,
      playerSnapshot: `${playerName} level ${playerLevel} at ${positionText}`,
    },
  };
}

function healthPayload(config, knowledgeBase) {
  return {
    ok: true,
    service: 'eldera-ai-gateway',
    mode: config.mode,
    geminiEnabled: config.geminiEnabled,
    knowledge: knowledgeSummary(knowledgeBase),
    endpoints: {
      chat: '/v1/chat',
      health: '/health',
    },
  };
}

export function createGatewayServer(config = getGatewayConfig()) {
  const knowledgeBase = config.knowledgeBase || loadKnowledgeBase(config.kbDirectory || DEFAULT_KB_DIRECTORY);

  return http.createServer(async (request, response) => {
    const requestUrl = new URL(request.url || '/', 'http://ai-gateway.local');

    if (request.method === 'GET' && (requestUrl.pathname === '/health' || requestUrl.pathname === '/ready')) {
      sendJson(response, 200, healthPayload(config, knowledgeBase));
      return;
    }

    if (requestUrl.pathname !== '/v1/chat') {
      sendError(response, 404, 'NOT_FOUND', 'Gateway endpoint not found.');
      return;
    }

    if (request.method !== 'POST') {
      response.setHeader('Allow', 'POST');
      sendError(response, 405, 'METHOD_NOT_ALLOWED', 'Use POST for Copilot chat requests.');
      return;
    }

    let payload;
    try {
      payload = await readJsonBody(request, config.maxBodyBytes);
    } catch (error) {
      if (error.code === 'PAYLOAD_TOO_LARGE') {
        sendError(response, 413, 'PAYLOAD_TOO_LARGE', 'Copilot request is too large.');
        return;
      }
      sendError(response, 400, 'INVALID_JSON', 'Request body must be valid JSON.');
      return;
    }

    const requestId = payload && typeof payload === 'object' ? payload.requestId || '' : '';

    if (config.mode !== 'mock') {
      sendError(response, 503, 'PROVIDER_DISABLED', 'Only ai-gateway mock mode is enabled in this phase.', requestId);
      return;
    }

    const validation = validateChatRequest(payload, config);
    if (!validation.ok) {
      sendError(response, validation.status, validation.code, validation.message, requestId);
      return;
    }

    sendJson(response, 200, buildGatewayResponse(payload, validation.text, config, knowledgeBase));
  });
}

const modulePath = fileURLToPath(import.meta.url);
const invokedPath = process.argv[1] ? path.resolve(process.argv[1]) : '';

if (invokedPath === modulePath) {
  const config = getGatewayConfig();
  const server = createGatewayServer(config);
  server.listen(config.port, () => {
    const geminiState = config.geminiEnabled ? 'enabled-but-unused' : 'disabled';
    console.log(`eldera-ai-gateway listening on http://0.0.0.0:${config.port} mode=${config.mode} gemini=${geminiState}`);
  });
}