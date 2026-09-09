# Eldera Farming & Building Roadmap

## Goal

Turn farming and construction into a primary gameplay loop on top of the Tibia Global / OTServBR world while keeping the base `.otbm` immutable.

## Phase 1 - Farming vertical slice

Implemented on `feature/farming-system`:

- Pick (`item id 3456`) receives a client context-menu action named **Farm**.
- Farm reuses the normal `Use with...` target cursor, but first arms a short-lived server-side farming action through ExtendedOpcode `217`.
- The regular pick action remains unchanged when farming is not armed.
- Server validates that the player:
  - still owns a pick;
  - is on the same floor;
  - is within one tile of the target;
  - selected a supported tree/bush/rock resource.
- Farming ticks once per second.
- Each tick emits `CONST_ME_POFF` on the resource position.
- A material reward is granted after a random `1..3` hits.
- Initial wallet materials:
  - `wood`;
  - `stone`.
- Wallet persists in `player_materials`.
- Resource nodes share an in-memory depletion counter (`8..12` hits for the MVP).
- When a resource is depleted, its world item is removed for the rest of the current server session.
- There is no timed respawn. Resources return only when Canary restarts and reloads the immutable `.otbm`, matching the daily Global Server Save + shutdown/restart cycle.
- Materials are synchronized server -> client and displayed in the Materials/Build mini-window.

## Resource depletion model

For the current design there are no intermediate damaged sprites.

The visual flow is intentionally simple:

- tree/bush -> farming hits -> disappears;
- rock/boulder -> farming hits -> disappears;
- depleted resources remain absent until the next server restart;
- the original resource is restored automatically when `otservbr.otbm` is loaded again.

This avoids introducing artificial sprite variants that do not already exist in the client assets.

## Resource safety strategy

The global map contains quest and decorative objects that must not be altered accidentally. The farming service therefore has:

- explicit resource overrides;
- a resource blacklist;
- conservative name-based detection for ordinary trees/bushes/rocks;
- protection against action-bound map objects;
- server-authoritative distance, target and tool validation.

As testing identifies real item IDs around Thais and other zones, detection should move toward a curated resource catalog.

## Phase 2 - Resource catalog

- Catalogue common tree, bush, rock and ore IDs.
- Define per-node metadata:
  - material;
  - durability;
  - reward range;
  - hit effect.
- Exclude quest, protection-zone and special objects.
- Keep depletion as runtime removal until the daily map reload unless a future gameplay decision explicitly changes this rule.

## Phase 3 - Construction planning vertical slice

Implemented on `feature/farming-system`:

- The Materials panel is now **Materials & Build**.
- Wood and Stone expose compact item-sprite buttons for wall, door and window variants.
- Structure catalogue, item IDs and material costs are server-authoritative and synchronized to the client through ExtendedOpcode `217`.
- Selecting a structure enters a persistent build mode.
- Left-clicking map squares queues or unqueues multiple construction positions.
- Queued structures are represented by client-only green ghost items. They are never sent to Canary until confirmation, so they have no server collision or persistence.
- The panel shows planned tile count, total cost and available material.
- **Build** confirms the complete batch; **Cancel** removes all previews without spending anything.
- Canary revalidates every selected position before accepting the batch:
  - same floor and within seven squares of the player;
  - real tile and ground exist;
  - no existing player structure;
  - no house, protection zone, floor-change, blocking tile, creature, teleport or action-bound ground.
- A build batch can contain up to 40 tiles.
- Material is deducted only after runtime creation and DB reservation succeed; failures roll back the created runtime items/reservations.
- Confirmed structures persist in `player_structures` (database migration 58).
- A startup GlobalEvent reapplies persisted structures after the immutable OTBM has loaded, so player constructions survive the daily Server Save restart.

This is intentionally different from natural resources: player-created constructions survive the daily map reload, while farmed natural resources reset with the `.otbm`.

### Current construction MVP limitations

- Preview ghosts use the real item sprite tinted/marked green; exact alpha/transparency and local pathfinding behaviour must be validated in the browser build.
- Wall/door/window orientation is not yet auto-selected from neighbouring structures.
- Build permissions are intentionally conservative; claims, guild ownership and explicit buildable zones are not implemented yet.
- Demolition, repair and structure HP are not implemented yet.

## Phase 4 - Building system

Next iterations:

- validate and curate the visual wall/door/window item variants;
- automatic horizontal/vertical orientation and neighbour-aware wall joins;
- click-drag / start-to-end line planning for long walls;
- demolition and material refund rules;
- repair and structure HP;
- ownership / guild permissions;
- buildable/restricted zones and claims;
- floors, gates and additional structures;
- crafting and siege mechanics.

## Technical rule

The `.otbm` remains the immutable base world. Temporary natural-resource depletion lives only in the running world and resets on restart. Player-created structures live in a persistent database-backed world layer and are reapplied by Canary at runtime.
