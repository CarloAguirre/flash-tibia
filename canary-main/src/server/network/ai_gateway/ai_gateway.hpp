/**
 * Canary - A free and open-source MMORPG server emulator
 * Copyright (©) 2019–present OpenTibiaBR <opentibiabr@outlook.com>
 * Repository: https://github.com/opentibiabr/canary
 * License: https://github.com/opentibiabr/canary/blob/main/LICENSE
 * Contributors: https://github.com/opentibiabr/canary/graphs/contributors
 * Website: https://docs.opentibiabr.com/
 */

#pragma once

#include "lib/thread/thread_pool.hpp"

class AiGateway {
public:
	explicit AiGateway(ThreadPool &threadPool);

	AiGateway(const AiGateway &) = delete;
	void operator=(const AiGateway &) = delete;

	static AiGateway &getInstance();

	void sendChatResponse(uint32_t playerId, uint8_t opcode, std::string payload, std::string fallbackPayload);

private:
	static constexpr size_t MAX_RESPONSE_BYTES = 32768;

	ThreadPool &threadPool;
	bool curlAvailable = false;

	struct HttpResponse {
		long statusCode = 0;
		std::string body;
		std::string error;
	};

	struct ResponseBuffer {
		std::string body;
		size_t maxBytes = MAX_RESPONSE_BYTES;
	};

	HttpResponse postJson(const std::string &url, const std::string &payload, int32_t timeoutMs) const;
	void queuePlayerResponse(uint32_t playerId, uint8_t opcode, std::string body) const;
	static size_t writeCallback(void* contents, size_t size, size_t nmemb, void* userp);
};

constexpr auto g_aiGateway = AiGateway::getInstance;