local OPCODE_LANGUAGE = 1
local OPCODE_ELDERA_COPILOT = 216

local aiCopilotLibPath = CORE_DIRECTORY .. "/libs/ai_copilot"

local function moduleLoader(name)
	return dofile(aiCopilotLibPath .. "/" .. name .. ".lua")
end

local modulesToPreload = {
	["ai_copilot.codec"] = function()
		return moduleLoader("codec")
	end,
	["ai_copilot.context"] = function()
		return moduleLoader("context")
	end,
	["ai_copilot.gateway"] = function()
		return moduleLoader("gateway")
	end,
	["ai_copilot.validator"] = function()
		return moduleLoader("validator")
	end,
	["ai_copilot.mock"] = function()
		return moduleLoader("mock")
	end,
}

for name, loader in pairs(modulesToPreload) do
	if not package.preload[name] then
		package.preload[name] = loader
	end
end

local codec = require("ai_copilot.codec")
local contextBuilder = require("ai_copilot.context")
local gateway = require("ai_copilot.gateway")
local validator = require("ai_copilot.validator")
local mock = require("ai_copilot.mock")

local function sendExtendedOpcode(player, opcode, buffer)
	if player:sendExtendedOpcode(opcode, buffer) then
		return true
	end

	local networkMessage = NetworkMessage()
	networkMessage:addByte(0x32)
	networkMessage:addByte(opcode)
	networkMessage:addString(buffer, "sendCopilotEcho - buffer")
	networkMessage:sendToPlayer(player)
	networkMessage:delete()
	return true
end

local function sendCopilotResponse(player, buffer)
	buffer = buffer or ""

	local request = codec.decodeRequest(buffer)
	local valid, errorMessage = validator.validate(player, request, buffer)
	if not valid then
		sendExtendedOpcode(player, OPCODE_ELDERA_COPILOT, codec.encode({
			v = 1,
			type = "error",
			requestId = request.requestId,
			error = errorMessage,
		}))
		return
	end

	local context = contextBuilder.build(player)
	local response = mock.answer(request, context)
	if gateway.sendChat(player, OPCODE_ELDERA_COPILOT, request, context, response) then
		return
	end

	sendExtendedOpcode(player, OPCODE_ELDERA_COPILOT, codec.encode(response))
end

local extendedOpcode = CreatureEvent("ExtendedOpcode")

function extendedOpcode.onExtendedOpcode(player, opcode, buffer)
	if opcode == OPCODE_LANGUAGE then
		if buffer == "en" or buffer == "pt" then
		end
	elseif opcode == OPCODE_ELDERA_COPILOT then
		sendCopilotResponse(player, buffer)
	end
end

extendedOpcode:register()