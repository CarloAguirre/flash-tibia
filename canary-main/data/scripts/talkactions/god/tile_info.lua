local tileInfo = TalkAction("/tileinfo")

local function formatIds(items)
	if not items or #items == 0 then
		return "none"
	end

	local ids = {}
	for i = 1, #items do
		local item = items[i]
		if item then
			ids[#ids + 1] = tostring(item:getId())
		end
	end

	if #ids == 0 then
		return "none"
	end

	return table.concat(ids, ", ")
end

local function sendTileInfo(player, text)
	-- MESSAGE_STATUS_CONSOLE_BLUE resolves to MESSAGE_NONE on the current
	-- protocol and Canary intentionally rejects it. MESSAGE_EVENT_ADVANCE is
	-- a valid text-message type for protocol 15 and is already used elsewhere.
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, text)
end

function tileInfo.onSay(player, words, param)
	logCommand(player, words, param)

	param = tostring(param or "")
	local position = player:getPosition()
	if param:lower() == "front" then
		position:getNextPosition(player:getDirection())
	end

	local tile = Tile(position)
	if not tile then
		sendTileInfo(player, string.format(
			"TileInfo | pos=%d,%d,%d | tile=missing",
			position.x, position.y, position.z
		))
		return true
	end

	local ground = tile:getGround()
	local groundId = ground and ground:getId() or 0
	local items = tile:getItems()

	sendTileInfo(player, string.format(
		"TileInfo | pos=%d,%d,%d | ground=%d | items=[%s]",
		position.x, position.y, position.z, groundId, formatIds(items)
	))

	return true
end

tileInfo:separator(" ")
tileInfo:groupType("god")
tileInfo:register()
