/**
 * Canary - A free and open-source MMORPG server emulator
 * Copyright (©) 2019–present OpenTibiaBR <opentibiabr@outlook.com>
 * Repository: https://github.com/opentibiabr/canary
 * License: https://github.com/opentibiabr/canary/blob/main/LICENSE
 * Contributors: https://github.com/opentibiabr/canary/graphs/contributors
 * Website: https://docs.opentibiabr.com/
 */

#include "server/network/ai_gateway/ai_gateway.hpp"

#include "config/configmanager.hpp"
#include "creatures/players/player.hpp"
#include "game/game.hpp"
#include "game/scheduling/dispatcher.hpp"
#include "lib/di/container.hpp"
#include "server/network/message/networkmessage.hpp"

AiGateway::AiGateway(ThreadPool &threadPool) :
	threadPool(threadPool) {
	curlAvailable = curl_global_init(CURL_GLOBAL_ALL) == 0;
	if (!curlAvailable) {
		g_logger().error("Failed to init curl, Eldera Copilot gateway requests are disabled");
	}
}

AiGateway &AiGateway::getInstance() {
	return inject<AiGateway>();
}

void AiGateway::sendChatResponse(uint32_t playerId, uint8_t opcode, std::string payload, std::string fallbackPayload) {
	if (!g_configManager().getBoolean(AI_GATEWAY_ENABLED) || !curlAvailable) {
		queuePlayerResponse(playerId, opcode, std::move(fallbackPayload));
		return;
	}

	const auto &url = g_configManager().getString(AI_GATEWAY_URL);
	if (url.empty()) {
		queuePlayerResponse(playerId, opcode, std::move(fallbackPayload));
		return;
	}

	const auto configuredTimeoutMs = g_configManager().getNumber(AI_GATEWAY_TIMEOUT_MS);
	const auto timeoutMs = std::max<int32_t>(100, std::min<int32_t>(configuredTimeoutMs, 10000));

	threadPool.detach_task([this, playerId, opcode, payload = std::move(payload), fallbackPayload = std::move(fallbackPayload), url, timeoutMs]() mutable {
		const auto response = postJson(url, payload, timeoutMs);
		if (response.statusCode >= 200 && response.statusCode < 300 && !response.body.empty()) {
			queuePlayerResponse(playerId, opcode, response.body);
			return;
		}

		if (!response.error.empty()) {
			g_logger().warn("Eldera Copilot gateway request failed: {}", response.error);
		} else {
			g_logger().warn("Eldera Copilot gateway returned HTTP status {}", response.statusCode);
		}

		queuePlayerResponse(playerId, opcode, std::move(fallbackPayload));
	});
}

AiGateway::HttpResponse AiGateway::postJson(const std::string &url, const std::string &payload, int32_t timeoutMs) const {
	HttpResponse response;
	CURL* curl = curl_easy_init();
	if (!curl) {
		response.error = "curl_easy_init failed";
		return response;
	}

	curl_slist* headers = nullptr;
	headers = curl_slist_append(headers, "content-type: application/json");
	headers = curl_slist_append(headers, "accept: application/json");

	ResponseBuffer responseBuffer;
	curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
	curl_easy_setopt(curl, CURLOPT_POST, 1L);
	curl_easy_setopt(curl, CURLOPT_POSTFIELDS, payload.c_str());
	curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE_LARGE, static_cast<curl_off_t>(payload.size()));
	curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, &AiGateway::writeCallback);
	curl_easy_setopt(curl, CURLOPT_WRITEDATA, reinterpret_cast<void*>(&responseBuffer));
	curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);
	curl_easy_setopt(curl, CURLOPT_USERAGENT, "canary-eldera-copilot/phase1");
	curl_easy_setopt(curl, CURLOPT_NOSIGNAL, 1L);
	curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT_MS, timeoutMs);
	curl_easy_setopt(curl, CURLOPT_TIMEOUT_MS, timeoutMs);

	const CURLcode result = curl_easy_perform(curl);
	if (result != CURLE_OK) {
		response.error = curl_easy_strerror(result);
	} else {
		curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &response.statusCode);
		response.body = std::move(responseBuffer.body);
	}

	curl_slist_free_all(headers);
	curl_easy_cleanup(curl);
	return response;
}

void AiGateway::queuePlayerResponse(uint32_t playerId, uint8_t opcode, std::string body) const {
	g_dispatcher().addEvent([playerId, opcode, body = std::move(body)] {
		const auto &player = g_game().getPlayerByID(playerId);
		if (!player) {
			return;
		}

		NetworkMessage message;
		message.addByte(0x32);
		message.addByte(opcode);
		message.addString(body, std::source_location::current(), "AiGateway::queuePlayerResponse");
		player->sendNetworkMessage(message);
	}, "AiGateway::queuePlayerResponse");
}

size_t AiGateway::writeCallback(void* contents, size_t size, size_t nmemb, void* userp) {
	const size_t realSize = size * nmemb;
	auto* responseBuffer = static_cast<ResponseBuffer*>(userp);
	if (!responseBuffer || responseBuffer->body.size() + realSize > responseBuffer->maxBytes) {
		return 0;
	}

	responseBuffer->body.append(static_cast<char*>(contents), realSize);
	return realSize;
}