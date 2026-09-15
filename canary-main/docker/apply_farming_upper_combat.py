from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file_path = Path(path)
    text = file_path.read_text(encoding="utf-8")
    if old not in text:
        raise RuntimeError(f"Expected farming combat patch context not found in {path}: {old[:100]!r}")
    file_path.write_text(text.replace(old, new, 1), encoding="utf-8")


# Creature target acquisition and attack line-of-sight normally force both
# creatures onto the same z-level. Allow exactly one lower floor only when the
# attacker is a player standing on a runtime farming platform.
replace_once(
    "src/creatures/creature.cpp",
    '#include "creatures/combat/combat.hpp"\n#include "creatures/monsters/monster.hpp"',
    '#include "creatures/combat/combat.hpp"\n#include "creatures/combat/farming_platform_combat.hpp"\n#include "creatures/monsters/monster.hpp"',
)

replace_once(
    "src/creatures/creature.cpp",
    '''\t\tconst Position &creaturePos = creature->getPosition();\n\t\tif (creaturePos.z != getPosition().z || !canSee(creaturePos)) {\n\t\t\tm_attackedCreature.reset();\n\t\t\treturn false;\n\t\t}\n''',
    '''\t\tconst Position &creaturePos = creature->getPosition();\n\t\tconst bool farmingUpperFloorAttack = FarmingPlatformCombat::canAttackLowerFloor(getCreature(), creaturePos);\n\t\tif ((creaturePos.z != getPosition().z && !farmingUpperFloorAttack) || !canSee(creaturePos)) {\n\t\t\tm_attackedCreature.reset();\n\t\t\treturn false;\n\t\t}\n''',
)

replace_once(
    "src/creatures/creature.cpp",
    '''\tonAttacked();\n\tattackedCreature->onAttacked();\n\n\tif (g_game().isSightClear(getPosition(), attackedCreature->getPosition(), true)) {\n\t\tdoAttacking(interval);\n\t}\n''',
    '''\tonAttacked();\n\tattackedCreature->onAttacked();\n\n\tconst bool farmingUpperFloorAttack = FarmingPlatformCombat::canAttackLowerFloor(getCreature(), attackedCreature->getPosition());\n\tif (g_game().isSightClear(getPosition(), attackedCreature->getPosition(), !farmingUpperFloorAttack)) {\n\t\tdoAttacking(interval);\n\t}\n''',
)

# Combat::canDoCombat(tile) is the source of the "First go downstairs" rejection.
# Bypass only that z-level gate for an attacker standing on a marked farming
# platform and targeting the immediately lower floor; all other combat rules stay.
replace_once(
    "src/creatures/combat/combat.cpp",
    '#include "creatures/combat/combat.hpp"\n\n#include "config/configmanager.hpp"',
    '#include "creatures/combat/combat.hpp"\n#include "creatures/combat/farming_platform_combat.hpp"\n\n#include "config/configmanager.hpp"',
)

replace_once(
    "src/creatures/combat/combat.cpp",
    '''\tif (caster) {\n\t\tconst Position &casterPosition = caster->getPosition();\n\t\tconst Position &tilePosition = tile->getPosition();\n\t\tif (casterPosition.z < tilePosition.z) {\n\t\t\treturn RETURNVALUE_FIRSTGODOWNSTAIRS;\n\t\t} else if (casterPosition.z > tilePosition.z) {\n\t\t\treturn RETURNVALUE_FIRSTGOUPSTAIRS;\n\t\t}\n''',
    '''\tif (caster) {\n\t\tconst Position &casterPosition = caster->getPosition();\n\t\tconst Position &tilePosition = tile->getPosition();\n\t\tif (!FarmingPlatformCombat::canAttackLowerFloor(caster, tilePosition)) {\n\t\t\tif (casterPosition.z < tilePosition.z) {\n\t\t\t\treturn RETURNVALUE_FIRSTGODOWNSTAIRS;\n\t\t\t} else if (casterPosition.z > tilePosition.z) {\n\t\t\t\treturn RETURNVALUE_FIRSTGOUPSTAIRS;\n\t\t\t}\n\t\t}\n''',
)

# Weapon validation has its own same-floor gate. Permit the same one-floor-down
# exception here too, for both melee and ranged attacks.
replace_once(
    "src/items/weapons/weapons.cpp",
    '#include "creatures/combat/combat.hpp"\n#include "game/game.hpp"',
    '#include "creatures/combat/combat.hpp"\n#include "creatures/combat/farming_platform_combat.hpp"\n#include "game/game.hpp"',
)

replace_once(
    "src/items/weapons/weapons.cpp",
    '''\tconst Position &playerPos = player->getPosition();\n\tconst Position &targetPos = target->getPosition();\n\tif (playerPos.z != targetPos.z) {\n\t\treturn 0;\n\t}\n''',
    '''\tconst Position &playerPos = player->getPosition();\n\tconst Position &targetPos = target->getPosition();\n\tif (playerPos.z != targetPos.z && !FarmingPlatformCombat::canAttackLowerFloor(player, targetPos)) {\n\t\treturn 0;\n\t}\n''',
)

print("Applied farming upper-floor combat patch.")
