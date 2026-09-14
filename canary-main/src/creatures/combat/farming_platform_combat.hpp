#pragma once

#include "creatures/creature.hpp"
#include "items/item.hpp"
#include "items/tile.hpp"

namespace FarmingPlatformCombat {
	inline constexpr std::string_view PLATFORM_ATTRIBUTE = "farmingUpperFloor";

	inline bool isStandingOnUpperPlatform(const std::shared_ptr<Creature> &attacker) {
		if (!attacker || !attacker->getPlayer()) {
			return false;
		}

		const auto &tile = attacker->getTile();
		if (!tile) {
			return false;
		}

		const auto &ground = tile->getGround();
		return ground && ground->getCustomAttribute(std::string(PLATFORM_ATTRIBUTE)) != nullptr;
	}

	inline bool canAttackLowerFloor(const std::shared_ptr<Creature> &attacker, const Position &targetPosition) {
		if (!isStandingOnUpperPlatform(attacker)) {
			return false;
		}

		const Position &attackerPosition = attacker->getPosition();
		return targetPosition.z == attackerPosition.z + 1;
	}
}
