-- Construction enhancements layered on top of the base Farming implementation.
-- Keeps the original farming system backward compatible while adding orientation
-- metadata, orientation-aware persistence, and lightweight build feedback.

if not Farming then
	return
end

Farming.BUILD_ORIENTATION_HORIZONTAL = 0
Farming.BUILD_ORIENTATION_VERTICAL = 1

-- Curated two-direction pairs verified against the repository item catalogue.
-- Wall ranges contain several corner/junction sprites without explicit orientation
-- metadata, so wall rotation stays disabled until its exact straight pair is known.
if Farming.buildCatalog.wood and Farming.buildCatalog.wood.door then
	Farming.buildCatalog.wood.door.rotatedItemId = 5281
end
if Farming.buildCatalog.stone and Farming.buildCatalog.stone.door then
	Farming.buildCatalog.stone.door.rotatedItemId = 5281
end
if Farming.buildCatalog.wood and Farming.buildCatalog.wood.window then
	Farming.buildCatalog.wood.window.rotatedItemId = 5276
end
if Farming.buildCatalog.stone and Farming.buildCatalog.stone.window then
	Farming.buildCatalog.stone.window.rotatedItemId = 1471
end

local function buildPositionKey(position)
	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local function isWithinBuildRange(player, position)
	local playerPosition = player:getPosition()
	if playerPosition.z ~= position.z then
		return false
	end

	return math.max(math.abs(playerPosition.x - position.x), math.abs(playerPosition.y - position.y)) <= Farming.BUILD_MAX_RANGE
end

local function buildError(player, message)
	player:sendExtendedOpcode(Farming.OPCODE, "build|error|" .. tostring(message))
	player:sendCancelMessage(message)
end

local function parseBuildPayload(rawPayload)
	local orientation = Farming.BUILD_ORIENTATION_HORIZONTAL
	local rawPositions = tostring(rawPayload or "")
	local orientationToken, positionsToken = rawPositions:match("^([01])|(.+)$")
	if orientationToken and positionsToken then
		orientation = tonumber(orientationToken) or Farming.BUILD_ORIENTATION_HORIZONTAL
		rawPositions = positionsToken
	end

	local positions = {}
	local seen = {}
	for token in rawPositions:gmatch("[^;]+") do
		local x, y, z = token:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
		if not x then
			return nil, nil, "Invalid build position."
		end

		local position = Position(tonumber(x), tonumber(y), tonumber(z))
		local key = buildPositionKey(position)
		if not seen[key] then
			seen[key] = true
			positions[#positions + 1] = position
			if #positions > Farming.BUILD_MAX_TILES then
				return nil, nil, string.format("You can queue at most %d tiles at once.", Farming.BUILD_MAX_TILES)
			end
		end
	end

	if #positions == 0 then
		return nil, nil, "Select at least one tile to build."
	end

	return positions, orientation
end

local function validateBuildTile(player, position)
	if not isWithinBuildRange(player, position) then
		return false, "All construction tiles must be within 7 squares of your character."
	end

	local key = buildPositionKey(position)
	if Farming.structurePositions[key] then
		return false, "There is already a player structure on one of the selected tiles."
	end

	local tile = Tile(position)
	if not tile or not tile:getGround() then
		return false, "One of the selected tiles is not buildable."
	end

	if tile:hasFlag(TILESTATE_HOUSE) then
		return false, "Building inside houses is disabled for now."
	end
	if tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		return false, "Building in protection zones is disabled."
	end
	if tile:hasFlag(TILESTATE_FLOORCHANGE) then
		return false, "You cannot build on stairs, ramps or floor changes."
	end
	if tile:hasFlag(TILESTATE_BLOCKSOLID) then
		return false, "One of the selected tiles is already blocked."
	end
	if tile:getCreatureCount() > 0 then
		return false, "A creature is standing on one of the selected tiles."
	end
	if tile:getItemByType(ITEM_TYPE_TELEPORT) then
		return false, "You cannot build on a teleport."
	end

	local ground = tile:getGround()
	if ground and ground:getActionId() ~= 0 then
		return false, "You cannot build on a special map tile."
	end

	return true
end

local function cleanupBuiltItems(items)
	for _, item in ipairs(items) do
		if item then
			item:remove()
		end
	end
end

local function spendMaterial(player, material, amount)
	local wallet = Farming.getWallet(player)
	if (wallet[material] or 0) < amount then
		return false
	end

	if not db.query(string.format(
		"UPDATE `player_materials` SET `amount` = `amount` - %d WHERE `player_id` = %d AND `material` = '%s' AND `amount` >= %d",
		amount,
		player:getGuid(),
		material,
		amount
	)) then
		return false
	end

	Farming.sendWallet(player)
	return true
end

local function constructionEffect(x, y, z, effect)
	Position(x, y, z):sendMagicEffect(effect)
end

-- Keep the legacy catalogue packets for old clients and append an orientation-
-- aware packet consumed by the enhanced browser client.
local baseSendBuildCatalog = Farming.sendBuildCatalog
function Farming.sendBuildCatalog(player)
	baseSendBuildCatalog(player)

	for material, structures in pairs(Farming.buildCatalog) do
		local parts = { "catalog2", material }
		for _, structureType in ipairs({ "wall", "door", "window" }) do
			local config = structures[structureType]
			if config then
				parts[#parts + 1] = structureType
				parts[#parts + 1] = tostring(config.itemId)
				parts[#parts + 1] = tostring(config.rotatedItemId or config.itemId)
				parts[#parts + 1] = tostring(config.cost)
			end
		end
		player:sendExtendedOpcode(Farming.OPCODE, table.concat(parts, "|"))
	end
end

-- Replaces only the build confirmation slice. The persisted item_id is the
-- actually selected orientation, so the existing restore logic needs no schema
-- change and restores the same direction after server restart.
function Farming.confirmBuild(player, material, structureType, rawPayload)
	local materialCatalog = Farming.buildCatalog[material]
	local config = materialCatalog and materialCatalog[structureType] or nil
	if not config then
		buildError(player, "Unknown construction type.")
		return true
	end

	local positions, orientation, parseError = parseBuildPayload(rawPayload)
	if not positions then
		buildError(player, parseError)
		return true
	end

	if orientation == Farming.BUILD_ORIENTATION_VERTICAL and not config.rotatedItemId then
		buildError(player, "This construction does not have a validated rotated variant.")
		return true
	end

	for _, position in ipairs(positions) do
		local valid, reason = validateBuildTile(player, position)
		if not valid then
			buildError(player, reason)
			return true
		end
	end

	local itemId = config.itemId
	if orientation == Farming.BUILD_ORIENTATION_VERTICAL and config.rotatedItemId then
		itemId = config.rotatedItemId
	end

	local totalCost = config.cost * #positions
	local wallet = Farming.getWallet(player)
	if (wallet[material] or 0) < totalCost then
		buildError(player, string.format("You need %d %s for this construction.", totalCost, material))
		return true
	end

	local createdItems = {}
	for _, position in ipairs(positions) do
		local created = Game.createItem(itemId, 1, position)
		if not created then
			cleanupBuiltItems(createdItems)
			buildError(player, "The server could not create one of the structures.")
			return true
		end
		createdItems[#createdItems + 1] = created
	end

	local values = {}
	for _, position in ipairs(positions) do
		values[#values + 1] = string.format(
			"(%d, '%s', '%s', %d, %d, %d, %d)",
			player:getGuid(), material, structureType, itemId, position.x, position.y, position.z
		)
	end

	local insertOk = db.query(
		"INSERT INTO `player_structures` (`player_id`, `material`, `structure_type`, `item_id`, `pos_x`, `pos_y`, `pos_z`) VALUES " .. table.concat(values, ",")
	)
	if not insertOk then
		cleanupBuiltItems(createdItems)
		buildError(player, "Those tiles could not be reserved for construction.")
		return true
	end

	if not spendMaterial(player, material, totalCost) then
		cleanupBuiltItems(createdItems)
		local conditions = {}
		for _, position in ipairs(positions) do
			conditions[#conditions + 1] = string.format("(`pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d)", position.x, position.y, position.z)
		end
		db.query("DELETE FROM `player_structures` WHERE `player_id`=" .. player:getGuid() .. " AND (" .. table.concat(conditions, " OR ") .. ")")
		buildError(player, "Your material balance changed before construction was confirmed.")
		return true
	end

	for index, position in ipairs(positions) do
		Farming.structurePositions[buildPositionKey(position)] = true
		local delay = ((index - 1) * 75) + 1
		addEvent(constructionEffect, delay, position.x, position.y, position.z, CONST_ME_POFF)
		addEvent(constructionEffect, delay + 140, position.x, position.y, position.z, CONST_ME_BLOCKHIT)
	end

	local newWallet = Farming.getWallet(player)
	player:sendExtendedOpcode(
		Farming.OPCODE,
		string.format(
			"build|success|%s|%s|%d|%d|%d|%d",
			material,
			structureType,
			#positions,
			totalCost,
			newWallet[material] or 0,
			orientation
		)
	)
	player:sendTextMessage(
		MESSAGE_EVENT_ADVANCE,
		string.format("Built %d %s structure%s for %d %s.", #positions, structureType, #positions == 1 and "" or "s", totalCost, material)
	)
	return true
end
