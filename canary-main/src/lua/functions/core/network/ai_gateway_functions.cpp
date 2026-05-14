/**
 * Canary - A free and open-source MMORPG server emulator
 * Copyright (©) 2019–present OpenTibiaBR <opentibiabr@outlook.com>
 * Repository: https://github.com/opentibiabr/canary
 * License: https://github.com/opentibiabr/canary/blob/main/LICENSE
 * Contributors: https://github.com/opentibiabr/canary/graphs/contributors
 * Website: https://docs.opentibiabr.com/
 */

#include "lua/functions/core/network/ai_gateway_functions.hpp"

#include "creatures/players/player.hpp"
#include "lua/functions/lua_functions_loader.hpp"
#include "server/network/ai_gateway/ai_gateway.hpp"

void AiGatewayFunctions::init(lua_State* L) {
	Lua::registerTable(L, "AiGateway");
	Lua::registerMethod(L, "AiGateway", "sendChatResponse", AiGatewayFunctions::luaAiGatewaySendChatResponse);
}

int AiGatewayFunctions::luaAiGatewaySendChatResponse(lua_State* L) {
	// AiGateway.sendChatResponse(player, opcode, payload, fallbackPayload)
	const auto &player = Lua::getPlayer(L, 1);
	if (!player) {
		Lua::reportErrorFunc(Lua::getErrorDesc(LUA_ERROR_PLAYER_NOT_FOUND));
		Lua::pushBoolean(L, false);
		return 1;
	}

	const auto opcode = Lua::getNumber<uint8_t>(L, 2);
	const auto payload = Lua::getString(L, 3);
	const auto fallbackPayload = Lua::getString(L, 4);
	if (payload.empty() || fallbackPayload.empty()) {
		Lua::pushBoolean(L, false);
		return 1;
	}

	g_aiGateway().sendChatResponse(player->getID(), opcode, payload, fallbackPayload);
	Lua::pushBoolean(L, true);
	return 1;
}