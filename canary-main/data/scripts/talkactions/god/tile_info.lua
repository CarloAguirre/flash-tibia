local tileInfo = TalkAction("/tileinfo")

local function formatIds(items)
	if not items or #items == 0 then
		return "none"
	end

	local ids = {}
	for i = 1, #items do
		ids[#ids + 1] = tostring(items[i]:getId())
	end
	return table.concat(ids, ", ")
end

function tileInfo.onSay(player, words, param)
	logCommand(player, words, param)

	local position = player:getPosition()
	if param:lower() == "front" then
		position:getNextPosition(player:getDirection())
	end

	local tile = Tile(position)
	if not tile then
		player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
			"TileInfo | pos=%d,%d,%d | tile=missing",
			position.x, position.y, position.z
		))
		return true
	end

	local ground = tile:getGround()
	local groundId = ground and ground:getId() or 0
	local items = tile:getItems()

	player:sendTextMessage(MESSAGE_STATUS_CONSOLE_BLUE, string.format(
		"TileInfo | pos=%d,%d,%d | ground=%d | items=[%s]",
		position.x, position.y, position.z, groundId, formatIds(items)
	))

	return true
end

tileInfo:separator(" ")
tileInfo:groupType("god")
tileInfo:register()
