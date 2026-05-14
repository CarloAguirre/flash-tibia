local validator = {}

local MAX_BUFFER_BYTES = 4096
local MAX_TEXT_BYTES = 240
local EXHAUSTION_KEY = "ai-copilot-chat"
local EXHAUSTION_SECONDS = 2

local allowedTypes = {
	chat = true,
	dummy = true,
}

function validator.validate(player, request, buffer)
	if #buffer > MAX_BUFFER_BYTES then
		return false, "Copilot request is too large."
	end

	if player:hasExhaustion(EXHAUSTION_KEY) then
		return false, "Please wait a moment before asking Copilot again."
	end

	if request.type == "" or not allowedTypes[request.type] then
		return false, "Unsupported Copilot request type."
	end

	if request.text == "" then
		return false, "Write a message before sending it to Copilot."
	end

	if #request.text > MAX_TEXT_BYTES then
		return false, "Copilot message is too long."
	end

	player:setExhaustion(EXHAUSTION_KEY, EXHAUSTION_SECONDS)
	return true
end

return validator