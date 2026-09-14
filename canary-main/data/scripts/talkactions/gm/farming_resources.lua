local farmingResources = TalkAction("/resources")

local VALID_MATERIALS = {
	wood = true,
	stone = true,
}

local function usage(player)
	player:sendCancelMessage("Usage: /resources <wood|stone|all> <amount>")
end

function farmingResources.onSay(player, words, param)
	logCommand(player, words, param)

	local normalized = tostring(param or ""):gsub(",", " ")
	local material, rawAmount = normalized:match("^%s*(%S+)%s+(%d+)%s*$")
	if not material or not rawAmount then
		usage(player)
		return true
	end

	material = material:lower()
	local amount = tonumber(rawAmount)
	if not amount or amount < 1 or amount > 1000000 then
		player:sendCancelMessage("Amount must be between 1 and 1000000.")
		return true
	end

	if material == "all" then
		if not Farming.addMaterial(player, "wood", amount) or not Farming.addMaterial(player, "stone", amount) then
			player:sendCancelMessage("Could not add farming resources.")
			return true
		end
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Added %d wood and %d stone.", amount, amount))
		return true
	end

	if not VALID_MATERIALS[material] then
		usage(player)
		return true
	end

	if not Farming.addMaterial(player, material, amount) then
		player:sendCancelMessage("Could not add farming resources.")
		return true
	end

	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Added %d %s.", amount, material))
	return true
end

farmingResources:separator(" ")
farmingResources:groupType("gamemaster")
farmingResources:register()
