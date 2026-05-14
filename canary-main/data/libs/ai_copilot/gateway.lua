local gateway = {}

local codec = require("ai_copilot.codec")

function gateway.sendChat(player, opcode, request, context, fallbackResponse)
	if not AiGateway or not AiGateway.sendChatResponse then
		return false
	end

	local payload = codec.encode({
		v = 1,
		requestId = request.requestId,
		type = request.type,
		text = request.text,
		context = context,
	})

	local ok, queued = pcall(AiGateway.sendChatResponse, player, opcode, payload, codec.encode(fallbackResponse))
	return ok and queued == true
end

return gateway