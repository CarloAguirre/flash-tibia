# Eldera AI Gateway

Internal Copilot backend for the Canary 15 stack.

Current phase: mock-only, read-only chat with a small curated knowledge base and deterministic recommendation cards. Gemini, routes, tasker, and action execution are intentionally disabled.

## Endpoints

- `GET /health`: service status and active mode.
- `GET /ready`: same payload as health for container readiness checks.
- `POST /v1/chat`: accepts a contextual Copilot chat request and returns a deterministic mock answer.

The response may include `cards`, `sources`, `knowledge`, and `recommender` metadata when the local KB or deterministic recommendation rules match the player's question. `route` remains `null` and `actions` remains an empty array in this phase.

Example request:

```json
{
  "v": 1,
  "requestId": "copilot-1",
  "type": "chat",
  "text": "where can I hunt?",
  "context": {
    "player": {
      "name": "Test Druid",
      "level": 8,
      "position": { "x": 100, "y": 200, "z": 7 }
    }
  }
}
```

## Environment

- `PORT`: HTTP port, default `8095`.
- `AI_GATEWAY_MODE`: only `mock` is supported in this phase.
- `GEMINI_ENABLED`: default `false`; exposed for future wiring, not used yet.
- `MAX_BODY_BYTES`: default `32768`.
- `MAX_TEXT_BYTES`: default `240`.
- `KB_DIRECTORY`: optional path to the curated KB directory, default `./kb`.

No Gemini key is read, logged, or required in this phase.

## Knowledge Base

The curated KB lives in `kb/`:

- `server_rules.json`: server rates, world policy, and Copilot phase policy.
- `locations.json`: starter and mainland location facts.
- `npcs.json`: selected NPC roles sourced from datapack scripts.
- `hunts.json`: early read-only hunting notes.
- `routes.json`: route metadata only; route overlays and autowalk are disabled.
- `recommendation_rules.json`: deterministic read-only rules for early contextual recommendations.
- `evals/golden.json`: golden retrieval and recommendation cases.

## Development

```bash
npm test --prefix ai-gateway
npm run validate:kb --prefix ai-gateway
npm run evaluate:kb --prefix ai-gateway
```

`validate:kb` loads every KB file, checks duplicate IDs and keyword shape, verifies all KB files use the same version, and confirms source references exist when run from the full repository workspace.

`evaluate:kb` runs golden retrieval and recommendation cases from `kb/evals/golden.json`. It catches ranking regressions such as a location question being answered by an NPC entry that only mentions that location, or a level 8 next-step question not resolving to The Oracle.