import assert from 'node:assert/strict';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';

import { buildGatewayResponse, createGatewayServer, validateChatRequest } from './server.js';
import { findKnowledgeMatches, loadKnowledgeBase, validateKnowledgeBase } from './kb.js';
import { findRecommendations } from './recommender.js';

const config = {
  mode: 'mock',
  geminiEnabled: false,
  maxBodyBytes: 32768,
  maxTextBytes: 240,
};

const knowledgeBase = loadKnowledgeBase(fileURLToPath(new URL('./kb', import.meta.url)));

test('validates chat requests', () => {
  const valid = validateChatRequest({ type: 'chat', text: ' where to hunt? ' }, config);
  assert.equal(valid.ok, true);
  assert.equal(valid.text, 'where to hunt?');

  const empty = validateChatRequest({ type: 'chat', text: '   ' }, config);
  assert.equal(empty.ok, false);
  assert.equal(empty.code, 'EMPTY_TEXT');
});

test('builds a read-only mock answer with context', () => {
  const response = buildGatewayResponse({
    requestId: 'copilot-test',
    context: {
      player: {
        name: 'Test Druid',
        level: 8,
        position: { x: 100, y: 200, z: 7 },
      },
    },
  }, 'where can I hunt at level 8?', config, knowledgeBase);

  assert.equal(response.type, 'answer');
  assert.equal(response.requestId, 'copilot-test');
  assert.equal(response.provider, 'mock');
  assert.equal(response.model, 'eldera-copilot-kb-mock-v1');
  assert.equal(response.requiresConfirmation, false);
  assert.equal(response.actions.length, 0);
  assert.equal(response.route, null);
  assert.ok(response.cards.length > 0);
  assert.ok(response.sources.length > 0);
  assert.equal(response.knowledge.version, 'eldera-kb-phase2-v1');
  assert.match(response.message, /Test Druid/);
});

test('loads and validates the curated knowledge base', () => {
  assert.equal(validateKnowledgeBase(knowledgeBase.files), true);
  assert.ok(knowledgeBase.entries.length >= 10);

  const matches = findKnowledgeMatches(knowledgeBase, 'where can I hunt rotworms?', { player: { level: 8 } });
  assert.equal(matches[0].kind, 'hunt');
  assert.match(matches[0].name, /rotworm/i);

  const npcMatches = findKnowledgeMatches(knowledgeBase, 'what does the oracle do?', { player: { level: 8 } });
  assert.equal(npcMatches[0].kind, 'npc');
  assert.match(npcMatches[0].name, /oracle/i);
});

test('returns a controlled no-data response for missing KB coverage', () => {
  const response = buildGatewayResponse({
    requestId: 'missing-kb',
    context: { player: { name: 'Tester', level: 8, position: { x: 1, y: 2, z: 3 } } },
  }, 'how do I tame a crystal spaceship?', config, knowledgeBase);

  assert.equal(response.cards.length, 0);
  assert.match(response.message, /No tengo ese dato/);
});

test('builds deterministic read-only recommendation cards', () => {
  const context = { player: { name: 'Test Knight', level: 8, position: { x: 1, y: 2, z: 3 } } };
  const recommendations = findRecommendations(knowledgeBase, 'what should I do next at level 8?', context);
  assert.equal(recommendations[0].id, 'recommendation.oracle_level_8');

  const response = buildGatewayResponse({
    requestId: 'recommendation-test',
    context,
  }, 'what should I do next at level 8?', config, knowledgeBase);

  assert.equal(response.requestId, 'recommendation-test');
  assert.equal(response.cards[0].id, 'recommendation.oracle_level_8');
  assert.equal(response.cards[0].type, 'recommendation');
  assert.equal(response.sources[0].id, 'recommendation.oracle_level_8');
  assert.equal(response.recommender.mode, 'deterministic');
  assert.ok(response.recommender.matched > 0);
  assert.equal(response.route, null);
  assert.equal(response.actions.length, 0);
  assert.equal(response.requiresConfirmation, false);
  assert.match(response.message, /read-only guidance/);
});

test('builds preview-only route responses without actions', () => {
  const response = buildGatewayResponse({
    requestId: 'route-test',
    context: { player: { name: 'Route Tester', level: 8, position: { x: 32104, y: 32189, z: 7 } } },
  }, 'show me the route to the oracle in Rookgaard', config, knowledgeBase);

  assert.equal(response.requestId, 'route-test');
  assert.equal(response.route.id, 'route.rookgaard_oracle');
  assert.equal(response.route.status, 'preview-only');
  assert.equal(response.route.previewOnly, true);
  assert.ok(response.route.waypoints.length >= 2);
  assert.equal(response.route.actions.length, 0);
  assert.equal(response.route.requiresConfirmation, false);
  assert.equal(response.actions.length, 0);
  assert.equal(response.requiresConfirmation, false);
  assert.match(response.message, /does not move your character/);
});

test('serves the chat endpoint over HTTP', async () => {
  const server = createGatewayServer({ ...config, knowledgeBase });
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));

  try {
    const address = server.address();
    const response = await fetch(`http://127.0.0.1:${address.port}/v1/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        v: 1,
        requestId: 'http-test',
        type: 'chat',
        text: 'phase one gateway test',
        context: { player: { name: 'Tester', level: 1, position: { x: 1, y: 2, z: 3 } } },
      }),
    });

    const payload = await response.json();
    assert.equal(response.status, 200);
    assert.equal(payload.requestId, 'http-test');
    assert.equal(payload.echo, 'phase one gateway test');
    assert.equal(payload.knowledge.version, 'eldera-kb-phase2-v1');
  } finally {
    await new Promise((resolve) => server.close(resolve));
  }
});