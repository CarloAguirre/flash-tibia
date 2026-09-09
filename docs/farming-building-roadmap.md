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
- Resource nodes share an in-memory depletion counter (`8..12` hits for the MVP) and recover after 30 seconds.
- Materials are synchronized server -> client and displayed in a `Materials` mini-window.

### Current MVP limitation

Depletion is logical but not yet visually destructive: the world item remains visible while the node is recovering. Visual states (tree -> damaged tree -> stump; rock -> damaged rock -> rubble) will be added only after the global-map resource item IDs and safe transform pairs are catalogued. This avoids damaging quest/special map objects.

## Resource safety strategy

The global map contains quest and decorative objects that must not be altered accidentally. The farming service therefore has:

- explicit resource overrides;
- a resource blacklist;
- conservative name-based detection for ordinary trees/bushes/rocks;
- server-authoritative distance, target and tool validation.

As testing identifies real item IDs around Thais and other zones, detection should move toward a curated resource catalog.

## Phase 2 - Resource catalog & visual depletion

- Catalogue common tree, bush, rock and ore IDs.
- Define per-node metadata:
  - material;
  - durability;
  - reward range;
  - hit effect;
  - depleted item ID;
  - respawn item ID;
  - respawn delay.
- Add visual transform/restore states.
- Exclude quest, protection-zone and special objects.

## Phase 3 - Persistent world resources

Persist dynamic resource state independently of the `.otbm`:

- world position;
- original item ID;
- current state;
- remaining durability;
- depleted/respawn timestamp.

This state is restored after a Canary restart.

## Phase 4 - Construction MVP

Use wallet materials to build a first structure (wood wall):

- enter build mode;
- select a neighboring tile;
- validate build permissions server-side;
- spend wallet materials;
- create blocking world item;
- persist structure in DB;
- restore it after server restart.

## Phase 5 - Building system

- wood/stone walls;
- doors and gates;
- floors;
- repair/demolition;
- structure HP;
- ownership / guild permissions;
- buildable/restricted zones;
- claims;
- crafting and siege mechanics.

## Technical rule

The `.otbm` remains the immutable base world. Player-created changes live in a dynamic database-backed world layer and are reapplied by Canary at runtime.
