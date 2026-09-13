-- Player-built upper platforms, stairs and catapults.
-- This layer extends the farming/building system without changing native map objects.

if not Farming then
	return
end

local PLATFORM_FLOOR_ITEM_ID = 408
local STAIR_NORTH_ITEM_ID = 1958
local STAIR_WEST_ITEM_ID = 7881
local STAIR_COST = 12
local CATAPULT_COST = 30
local CATAPULT_BUILD_MS = 2000
local CATAPULT_RANGE = 7
local CATAPULT_OPERATOR_RANGE = 3
local CATAPULT_COOLDOWN_SECONDS = 2
local CATAPULT_MIN_DAMAGE = 35
local CATAPULT_MAX_DAMAGE = 80

local CATAPULT_PARTS = {
	{ structureType = "catapult_nw", itemId = 5609, dx = 0, dy = 0 },
	{ structureType = "catapult_ne", itemId = 5610, dx = 1, dy = 0 },
	{ structureType = "catapult_sw", itemId = 5611, dx = 0, dy = 1 },
	{ structureType = "catapult_se", itemId = 5612, dx = 1, dy = 1 },
}

local CATAPULT_TYPES = {
	catapult_nw = true,
	catapult_ne = true,
	catapult_sw = true,
	catapult_se = true,
}

Farming.catapultCooldowns = Farming.catapultCooldowns or {}
Farming.buildCatalog.wood.stair = {
	itemId = STAIR_NORTH_ITEM_ID,
	rotatedItemId = STAIR_WEST_ITEM_ID,
	cost = STAIR_COST,
	label = "Wood Stair",
}
Farming.buildCatalog.wood.catapult = {
	itemId = 5609,
	cost = CATAPULT_COST,
	label = "Catapult",
}

local function positionKey(position)
	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local function copyPosition(position)
	return Position(position.x, position.y, position.z)
end

local function chebyshevDistance(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function buildError(player, message)
	player:sendExtendedOpcode(Farming.OPCODE, "build|error|" .. tostring(message))
	player:sendCancelMessage(message)
end

local function siegeError(player, message)
	player:sendExtendedOpcode(Farming.OPCODE, "siege|fire|error|" .. tostring(message))
	player:sendCancelMessage(message)
end

local function spendMaterial(player, material, amount)
	local wallet = Farming.getWallet(player)
	if (wallet[material] or 0) < amount then
		return false
	end

	local ok = db.query(string.format(
		"UPDATE `player_materials` SET `amount`=`amount`-%d WHERE `player_id`=%d AND `material`='%s' AND `amount`>=%d",
		amount,
		player:getGuid(),
		material,
		amount
	))
	if not ok then
		return false
	end

	Farming.sendWallet(player)
	return true
end

local function refundMaterial(playerGuid, material, amount)
	if amount <= 0 then
		return
	end

	db.query(string.format(
		"INSERT INTO `player_materials` (`player_id`, `material`, `amount`) VALUES (%d, '%s', %d) " ..
		"ON DUPLICATE KEY UPDATE `amount`=`amount`+VALUES(`amount`)",
		playerGuid,
		material,
		amount
	))
end

local function parseBuildEntries(rawPayload)
	local raw = tostring(rawPayload or "")
	local entries = {}
	local seen = {}

	local v2 = raw:match("^v2|(.+)$")
	if v2 then
		for token in v2:gmatch("[^;]+") do
			local x, y, z, orientation = token:match("^(%-?%d+),(%-?%d+),(%-?%d+),([01])$")
			if not x then
				return nil, "Invalid special construction position."
			end
			local position = Position(tonumber(x), tonumber(y), tonumber(z))
			local key = positionKey(position)
			if not seen[key] then
				seen[key] = true
				entries[#entries + 1] = {
					position = position,
					orientation = tonumber(orientation) or 0,
				}
			end
		end
	else
		for token in raw:gmatch("[^;]+") do
			local x, y, z = token:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
			if not x then
				return nil, "Invalid special construction position."
			end
			local position = Position(tonumber(x), tonumber(y), tonumber(z))
			local key = positionKey(position)
			if not seen[key] then
				seen[key] = true
				entries[#entries + 1] = { position = position, orientation = 0 }
			end
		end
	end

	if #entries == 0 then
		return nil, "Select at least one tile to build."
	end
	return entries
end

local function getStairDestination(stairPosition, orientation)
	if orientation == 1 then
		return Position(stairPosition.x - 1, stairPosition.y, stairPosition.z - 1)
	end
	return Position(stairPosition.x, stairPosition.y - 1, stairPosition.z - 1)
end

local function getPreferredStairSupportPosition(stairPosition, orientation)
	local destination = getStairDestination(stairPosition, orientation)
	return Position(destination.x, destination.y, stairPosition.z)
end

local function ownsStructureAt(playerGuid, structureType, position)
	local query = db.storeQuery(string.format(
		"SELECT `id` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='%s' " ..
		"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
		playerGuid,
		structureType,
		position.x,
		position.y,
		position.z
	))
	if not query then
		return false
	end
	Result.free(query)
	return true
end

-- A stair's sprite orientation determines the direction it climbs, but the wall
-- supporting it does not have to be on that exact side. Prefer the natural
-- support tile for the selected sprite and then accept any orthogonally adjacent
-- player-built wall. This keeps placement intuitive around corners and wall runs.
local function findStairSupportPosition(playerGuid, stairPosition, orientation)
	local preferred = getPreferredStairSupportPosition(stairPosition, orientation)
	if ownsStructureAt(playerGuid, "wall", preferred) then
		return preferred
	end

	local candidates = {
		Position(stairPosition.x, stairPosition.y - 1, stairPosition.z), -- north
		Position(stairPosition.x - 1, stairPosition.y, stairPosition.z), -- west
		Position(stairPosition.x + 1, stairPosition.y, stairPosition.z), -- east
		Position(stairPosition.x, stairPosition.y + 1, stairPosition.z), -- south
	}
	for _, candidate in ipairs(candidates) do
		if ownsStructureAt(playerGuid, "wall", candidate) then
			return candidate
		end
	end

	return nil
end

local function validateStairSupports(player, rawPayload)
	local entries, parseError = parseBuildEntries(rawPayload)
	if not entries then
		return false, parseError
	end

	for _, entry in ipairs(entries) do
		if entry.position.z <= 0 then
			return false, "There is no upper floor available here."
		end
		local supportPosition = findStairSupportPosition(player:getGuid(), entry.position, entry.orientation)
		if not supportPosition then
			return false, "A wood stair must be directly next to one of your built walls."
		end
	end

	return true
end

local function ensureDynamicFloor(position)
	local tile = Tile(position)
	if not tile then
		Game.createTile(position, true)
		tile = Tile(position)
	end
	if not tile then
		return false
	end

	local ground = tile:getGround()
	if ground then
		return ground:getId() == PLATFORM_FLOOR_ITEM_ID
	end

	local created = Game.createItem(PLATFORM_FLOOR_ITEM_ID, 1, position)
	return created ~= nil
end

local function platformRowExists(playerGuid, position)
	return ownsStructureAt(playerGuid, "platform", position)
end

local function persistPlatformTile(playerGuid, position)
	if platformRowExists(playerGuid, position) then
		ensureDynamicFloor(position)
		Farming.structurePositions[positionKey(position)] = nil
		return true
	end

	local collision = db.storeQuery(string.format(
		"SELECT `id` FROM `player_structures` WHERE `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
		position.x,
		position.y,
		position.z
	))
	if collision then
		Result.free(collision)
		return false
	end

	if not ensureDynamicFloor(position) then
		return false
	end

	local inserted = db.query(string.format(
		"INSERT INTO `player_structures` (`player_id`, `material`, `structure_type`, `item_id`, `pos_x`, `pos_y`, `pos_z`) " ..
		"VALUES (%d, 'wood', 'platform', %d, %d, %d, %d)",
		playerGuid,
		PLATFORM_FLOOR_ITEM_ID,
		position.x,
		position.y,
		position.z
	))
	if not inserted then
		local tile = Tile(position)
		local ground = tile and tile:getGround() or nil
		if ground and ground:getId() == PLATFORM_FLOOR_ITEM_ID then
			ground:remove()
		end
		return false
	end

	-- A platform is walkable support, not an occupied construction slot.
	Farming.structurePositions[positionKey(position)] = nil
	return true
end

local function loadOwnedWalls(playerGuid, z)
	local walls = {}
	local query = db.storeQuery(string.format(
		"SELECT `pos_x`, `pos_y`, `pos_z` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='wall' AND `pos_z`=%d",
		playerGuid,
		z
	))
	if not query then
		return walls
	end

	repeat
		local position = Position(
			Result.getNumber(query, "pos_x"),
			Result.getNumber(query, "pos_y"),
			Result.getNumber(query, "pos_z")
		)
		walls[positionKey(position)] = position
	until not Result.next(query)
	Result.free(query)
	return walls
end

local function collectConnectedWalls(walls, seed)
	local seedKey = positionKey(seed)
	if not walls[seedKey] then
		return {}
	end

	local queue = { walls[seedKey] }
	local queued = { [seedKey] = true }
	local connected = {}
	local cursor = 1

	while cursor <= #queue and #connected < Farming.BUILD_MAX_TILES do
		local current = queue[cursor]
		cursor = cursor + 1
		connected[#connected + 1] = current

		for dx = -1, 1 do
			for dy = -1, 1 do
				if not (dx == 0 and dy == 0) then
					local neighbor = Position(current.x + dx, current.y + dy, current.z)
					local key = positionKey(neighbor)
					if walls[key] and not queued[key] then
						queued[key] = true
						queue[#queue + 1] = walls[key]
					end
				end
			end
		end
	end

	return connected
end

local function generatePlatformFromStair(playerGuid, stairPosition, orientation)
	local supportPosition = findStairSupportPosition(playerGuid, stairPosition, orientation)
	if not supportPosition then
		return 0
	end

	local walls = loadOwnedWalls(playerGuid, stairPosition.z)
	local connectedWalls = collectConnectedWalls(walls, supportPosition)
	local createdCount = 0

	for _, wallPosition in ipairs(connectedWalls) do
		local upperPosition = Position(wallPosition.x, wallPosition.y, wallPosition.z - 1)
		if persistPlatformTile(playerGuid, upperPosition) then
			createdCount = createdCount + 1
		end
	end

	return createdCount
end

local function catapultPartPosition(anchor, part)
	return Position(anchor.x + part.dx, anchor.y + part.dy, anchor.z)
end

local function getCatapultAnchor(position, structureType)
	if structureType == "catapult_ne" then
		return Position(position.x - 1, position.y, position.z)
	elseif structureType == "catapult_sw" then
		return Position(position.x, position.y - 1, position.z)
	elseif structureType == "catapult_se" then
		return Position(position.x - 1, position.y - 1, position.z)
	end
	return copyPosition(position)
end

local function isCatapultIntact(playerGuid, anchor)
	for _, part in ipairs(CATAPULT_PARTS) do
		local position = catapultPartPosition(anchor, part)
		local query = db.storeQuery(string.format(
			"SELECT `id` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='%s' AND `item_id`=%d " ..
			"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
			playerGuid,
			part.structureType,
			part.itemId,
			position.x,
			position.y,
			position.z
		))
		if not query then
			return false
		end
		Result.free(query)
	end
	return true
end

local function removeCatapultGroup(playerGuid, anchor)
	for _, part in ipairs(CATAPULT_PARTS) do
		local position = catapultPartPosition(anchor, part)
		local tile = Tile(position)
		local item = tile and tile:getItemById(part.itemId) or nil
		if item then
			item:remove()
		end
		db.query(string.format(
			"DELETE FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='%s' AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d",
			playerGuid,
			part.structureType,
			position.x,
			position.y,
			position.z
		))
		Farming.structurePositions[positionKey(position)] = nil
	end
end

local function relocateCreaturesBeforeFloorRemoval(position)
	local tile = Tile(position)
	if not tile then
		return
	end
	local creatures = tile:getCreatures()
	if not creatures then
		return
	end

	local lowerPosition = Position(position.x, position.y, position.z + 1)
	for _, creature in ipairs(creatures) do
		creature:teleportTo(lowerPosition, true)
	end
end

local function loadPlatformRows(playerGuid, platformZ)
	local rows = {}
	local query = db.storeQuery(string.format(
		"SELECT `id`, `pos_x`, `pos_y`, `pos_z` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='platform' AND `pos_z`=%d ORDER BY `id`",
		playerGuid,
		platformZ
	))
	if not query then
		return rows
	end

	repeat
		local row = {
			id = Result.getNumber(query, "id"),
			position = Position(
				Result.getNumber(query, "pos_x"),
				Result.getNumber(query, "pos_y"),
				Result.getNumber(query, "pos_z")
			),
		}
		rows[positionKey(row.position)] = row
	until not Result.next(query)
	Result.free(query)
	return rows
end

local function connectedPlatformComponents(rows)
	local visited = {}
	local components = {}

	for key, row in pairs(rows) do
		if not visited[key] then
			local component = {}
			local queue = { row }
			visited[key] = true
			local cursor = 1

			while cursor <= #queue do
				local current = queue[cursor]
				cursor = cursor + 1
				component[#component + 1] = current

				for dx = -1, 1 do
					for dy = -1, 1 do
						if not (dx == 0 and dy == 0) then
							local neighbor = Position(current.position.x + dx, current.position.y + dy, current.position.z)
							local neighborKey = positionKey(neighbor)
							if rows[neighborKey] and not visited[neighborKey] then
								visited[neighborKey] = true
								queue[#queue + 1] = rows[neighborKey]
							end
						end
					end
				end
			end
			components[#components + 1] = component
		end
	end

	return components
end

local function componentHasSupport(playerGuid, component)
	for _, row in ipairs(component) do
		local lower = Position(row.position.x, row.position.y, row.position.z + 1)
		if ownsStructureAt(playerGuid, "wall", lower) then
			return true
		end
	end
	return false
end

local function removePlatformComponent(playerGuid, component)
	local catapultAnchors = {}

	for _, row in ipairs(component) do
		local query = db.storeQuery(string.format(
			"SELECT `structure_type` FROM `player_structures` WHERE `player_id`=%d " ..
			"AND `structure_type` IN ('catapult_nw','catapult_ne','catapult_sw','catapult_se') " ..
			"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
			playerGuid,
			row.position.x,
			row.position.y,
			row.position.z
		))
		if query then
			local structureType = Result.getString(query, "structure_type")
			Result.free(query)
			local anchor = getCatapultAnchor(row.position, structureType)
			catapultAnchors[positionKey(anchor)] = anchor
		end
	end

	for _, anchor in pairs(catapultAnchors) do
		removeCatapultGroup(playerGuid, anchor)
	end

	for _, row in ipairs(component) do
		relocateCreaturesBeforeFloorRemoval(row.position)
		local tile = Tile(row.position)
		local ground = tile and tile:getGround() or nil
		if ground and ground:getId() == PLATFORM_FLOOR_ITEM_ID then
			ground:remove()
		end
		db.query(string.format("DELETE FROM `player_structures` WHERE `id`=%d AND `player_id`=%d", row.id, playerGuid))
		Farming.structurePositions[positionKey(row.position)] = nil
	end
end

function Farming.refreshSupportedPlatforms(playerGuid, lowerZ)
	local platformZ = lowerZ - 1
	if platformZ < 0 then
		return
	end

	local rows = loadPlatformRows(playerGuid, platformZ)
	for _, component in ipairs(connectedPlatformComponents(rows)) do
		if not componentHasSupport(playerGuid, component) then
			removePlatformComponent(playerGuid, component)
		end
	end
end

local function restorePlatformTiles()
	local query = db.storeQuery("SELECT `player_id`, `pos_x`, `pos_y`, `pos_z` FROM `player_structures` WHERE `structure_type`='platform' ORDER BY `id`")
	if not query then
		return
	end

	repeat
		local position = Position(
			Result.getNumber(query, "pos_x"),
			Result.getNumber(query, "pos_y"),
			Result.getNumber(query, "pos_z")
		)
		ensureDynamicFloor(position)
	until not Result.next(query)
	Result.free(query)
end

local function clearPlatformReservationsAndPrune()
	local pairsToRefresh = {}
	local query = db.storeQuery("SELECT `player_id`, `pos_x`, `pos_y`, `pos_z` FROM `player_structures` WHERE `structure_type`='platform' ORDER BY `id`")
	if not query then
		return
	end

	repeat
		local playerGuid = Result.getNumber(query, "player_id")
		local position = Position(
			Result.getNumber(query, "pos_x"),
			Result.getNumber(query, "pos_y"),
			Result.getNumber(query, "pos_z")
		)
		Farming.structurePositions[positionKey(position)] = nil
		pairsToRefresh[string.format("%d:%d", playerGuid, position.z + 1)] = { playerGuid = playerGuid, lowerZ = position.z + 1 }
	until not Result.next(query)
	Result.free(query)

	for _, refresh in pairs(pairsToRefresh) do
		Farming.refreshSupportedPlatforms(refresh.playerGuid, refresh.lowerZ)
	end
end

local baseRestoreStructures = Farming.restoreStructures
function Farming.restoreStructures()
	restorePlatformTiles()
	local result = baseRestoreStructures()
	clearPlatformReservationsAndPrune()
	return result
end

local function isPlayerOnOwnPlatform(player)
	local position = player:getPosition()
	return ownsStructureAt(player:getGuid(), "platform", position)
end

local function validateCatapultAnchor(player, anchor)
	if not isPlayerOnOwnPlatform(player) then
		return false, "You must stand on your supported upper platform to build a catapult."
	end

	if chebyshevDistance(player:getPosition(), anchor) > 1 then
		return false, "Place the catapult next to your character."
	end

	for _, part in ipairs(CATAPULT_PARTS) do
		local position = catapultPartPosition(anchor, part)
		if not platformRowExists(player:getGuid(), position) then
			return false, "A catapult needs a complete 2x2 area of your supported upper floor."
		end
		if Farming.structurePositions[positionKey(position)] then
			return false, "One of the catapult squares is already occupied."
		end
		local tile = Tile(position)
		if not tile or not tile:getGround() then
			return false, "One of the catapult squares has no floor."
		end
		if tile:hasFlag(TILESTATE_BLOCKSOLID) or tile:getCreatureCount() > 0 then
			return false, "One of the catapult squares is blocked."
		end
	end

	return true
end

local function deleteCatapultRows(playerGuid, anchor)
	for _, part in ipairs(CATAPULT_PARTS) do
		local position = catapultPartPosition(anchor, part)
		db.query(string.format(
			"DELETE FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='%s' AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d",
			playerGuid,
			part.structureType,
			position.x,
			position.y,
			position.z
		))
		Farming.structurePositions[positionKey(position)] = nil
	end
end

local function constructionDust(anchor)
	for _, part in ipairs(CATAPULT_PARTS) do
		catapultPartPosition(anchor, part):sendMagicEffect(CONST_ME_POFF)
	end
end

local function completeCatapultBuild(playerId, playerGuid, anchorData, batchId)
	local anchor = Position(anchorData.x, anchorData.y, anchorData.z)
	local player = Player(playerId)
	if player and player:getGuid() ~= playerGuid then
		player = nil
	end

	local valid = true
	for _, part in ipairs(CATAPULT_PARTS) do
		local position = catapultPartPosition(anchor, part)
		if not platformRowExists(playerGuid, position) then
			valid = false
			break
		end
		local tile = Tile(position)
		if not tile or tile:hasFlag(TILESTATE_BLOCKSOLID) or tile:getCreatureCount() > 0 then
			valid = false
			break
		end
	end

	local createdItems = {}
	if valid then
		for _, part in ipairs(CATAPULT_PARTS) do
			local position = catapultPartPosition(anchor, part)
			local item = Game.createItem(part.itemId, 1, position)
			if not item then
				valid = false
				break
			end
			createdItems[#createdItems + 1] = item
		end
	end

	if not valid then
		for _, item in ipairs(createdItems) do
			item:remove()
		end
		deleteCatapultRows(playerGuid, anchor)
		refundMaterial(playerGuid, "wood", CATAPULT_COST)
		if player then
			Farming.sendWallet(player)
			player:sendExtendedOpcode(Farming.OPCODE, string.format("build|piece|%d|1|%d|%d|%d|0|failed", batchId, anchor.x, anchor.y, anchor.z))
			player:sendExtendedOpcode(Farming.OPCODE, string.format("build|success|wood|catapult|0|0|%d|1", Farming.getWallet(player).wood or 0))
			player:sendCancelMessage("The catapult area became unavailable; your wood was refunded.")
		end
		return
	end

	for _, part in ipairs(CATAPULT_PARTS) do
		local position = catapultPartPosition(anchor, part)
		Farming.structurePositions[positionKey(position)] = true
		position:sendMagicEffect(CONST_ME_BLOCKHIT)
	end

	if player then
		local wallet = Farming.sendWallet(player)
		player:sendExtendedOpcode(Farming.OPCODE, string.format("build|piece|%d|1|%d|%d|%d|0|built", batchId, anchor.x, anchor.y, anchor.z))
		player:sendExtendedOpcode(Farming.OPCODE, string.format("build|success|wood|catapult|1|%d|%d|0", CATAPULT_COST, wallet.wood or 0))
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Built a catapult for %d wood.", CATAPULT_COST))
		Farming.sendSiegeStatus(player)
	end
end

local function confirmCatapult(player, rawPayload)
	local entries, parseError = parseBuildEntries(rawPayload)
	if not entries then
		buildError(player, parseError)
		return true
	end
	if #entries ~= 1 then
		buildError(player, "Build one catapult at a time.")
		return true
	end

	local anchor = entries[1].position
	local valid, reason = validateCatapultAnchor(player, anchor)
	if not valid then
		buildError(player, reason)
		return true
	end

	local wallet = Farming.getWallet(player)
	if (wallet.wood or 0) < CATAPULT_COST then
		buildError(player, string.format("You need %d wood for a catapult.", CATAPULT_COST))
		return true
	end

	local values = {}
	for _, part in ipairs(CATAPULT_PARTS) do
		local position = catapultPartPosition(anchor, part)
		values[#values + 1] = string.format(
			"(%d, 'wood', '%s', %d, %d, %d, %d)",
			player:getGuid(),
			part.structureType,
			part.itemId,
			position.x,
			position.y,
			position.z
		)
	end

	local inserted = db.query(
		"INSERT INTO `player_structures` (`player_id`, `material`, `structure_type`, `item_id`, `pos_x`, `pos_y`, `pos_z`) VALUES " .. table.concat(values, ",")
	)
	if not inserted then
		buildError(player, "Those four squares could not be reserved for the catapult.")
		return true
	end

	if not spendMaterial(player, "wood", CATAPULT_COST) then
		deleteCatapultRows(player:getGuid(), anchor)
		buildError(player, "Your wood balance changed before the catapult was confirmed.")
		return true
	end

	for _, part in ipairs(CATAPULT_PARTS) do
		Farming.structurePositions[positionKey(catapultPartPosition(anchor, part))] = true
	end

	Farming.buildBatchSequence = (Farming.buildBatchSequence or 0) + 1
	local batchId = Farming.buildBatchSequence
	player:sendExtendedOpcode(Farming.OPCODE, string.format("build|accepted|%d|1|%d", batchId, CATAPULT_COST))
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Catapult construction started.")

	local anchorData = { x = anchor.x, y = anchor.y, z = anchor.z }
	addEvent(constructionDust, 1, anchorData)
	addEvent(constructionDust, 900, anchorData)
	addEvent(completeCatapultBuild, CATAPULT_BUILD_MS, player:getId(), player:getGuid(), anchorData, batchId)
	return true
end

local baseConfirmBuild = Farming.confirmBuild
function Farming.confirmBuild(player, material, structureType, rawPayload)
	if material == "wood" and structureType == "stair" then
		local valid, reason = validateStairSupports(player, rawPayload)
		if not valid then
			buildError(player, reason)
			return true
		end
		return baseConfirmBuild(player, material, structureType, rawPayload)
	elseif material == "wood" and structureType == "catapult" then
		return confirmCatapult(player, rawPayload)
	end
	return baseConfirmBuild(player, material, structureType, rawPayload)
end

-- The normal sequential builder invokes this hook when it exists. Stairs use it
-- to materialise a walkable upper platform over the connected wall cluster.
function Farming.onStructureBuilt(playerGuid, material, structureType, entry)
	if material == "wood" and structureType == "stair" then
		generatePlatformFromStair(playerGuid, entry.position, entry.orientation or 0)
	end
end

local function findNearbyCatapult(player)
	local playerPosition = player:getPosition()
	local bestAnchor = nil
	local bestDistance = math.huge
	local query = db.storeQuery(string.format(
		"SELECT `pos_x`, `pos_y`, `pos_z` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='catapult_nw' AND `pos_z`=%d",
		player:getGuid(),
		playerPosition.z
	))
	if not query then
		return nil
	end

	repeat
		local anchor = Position(
			Result.getNumber(query, "pos_x"),
			Result.getNumber(query, "pos_y"),
			Result.getNumber(query, "pos_z")
		)
		local distance = chebyshevDistance(playerPosition, anchor)
		if distance <= CATAPULT_OPERATOR_RANGE and distance < bestDistance and isCatapultIntact(player:getGuid(), anchor) then
			bestDistance = distance
			bestAnchor = anchor
		end
	until not Result.next(query)
	Result.free(query)
	return bestAnchor
end

function Farming.sendSiegeStatus(player)
	local onPlatform = isPlayerOnOwnPlatform(player)
	local catapult = onPlatform and findNearbyCatapult(player) or nil
	player:sendExtendedOpcode(
		Farming.OPCODE,
		string.format("siege|status|platform|%d|catapult|%d", onPlatform and 1 or 0, catapult and 1 or 0)
	)
end

function Farming.fireCatapult(player, targetId)
	if not isPlayerOnOwnPlatform(player) then
		siegeError(player, "You must be standing on your supported upper platform.")
		return true
	end

	local anchor = findNearbyCatapult(player)
	if not anchor then
		siegeError(player, "Stand within three squares of one of your intact catapults.")
		return true
	end

	local target = Creature(tonumber(targetId) or 0)
	if not target or target:getId() == player:getId() then
		siegeError(player, "Select a creature or player on the floor below.")
		return true
	end

	local playerPosition = player:getPosition()
	local targetPosition = target:getPosition()
	if targetPosition.z ~= playerPosition.z + 1 then
		siegeError(player, "The catapult can target only the floor directly below you.")
		return true
	end
	if math.max(math.abs(anchor.x - targetPosition.x), math.abs(anchor.y - targetPosition.y)) > CATAPULT_RANGE then
		siegeError(player, string.format("The target is outside the catapult's %d-square range.", CATAPULT_RANGE))
		return true
	end

	local now = os.time()
	local readyAt = Farming.catapultCooldowns[player:getGuid()] or 0
	if now < readyAt then
		siegeError(player, "The catapult is reloading.")
		return true
	end
	Farming.catapultCooldowns[player:getGuid()] = now + CATAPULT_COOLDOWN_SECONDS

	anchor:sendMagicEffect(CONST_ME_POFF)
	anchor:sendDistanceEffect(targetPosition, CONST_ANI_SMALLSTONE)
	local damage = math.random(CATAPULT_MIN_DAMAGE, CATAPULT_MAX_DAMAGE)
	doTargetCombatHealth(player, target, COMBAT_PHYSICALDAMAGE, -damage, -damage, CONST_ME_NONE)

	player:sendExtendedOpcode(Farming.OPCODE, string.format("siege|fire|success|%d|%d", target:getId(), damage))
	return true
end

local baseHandleOpcode = Farming.handleOpcode
function Farming.handleOpcode(player, buffer)
	buffer = tostring(buffer or "")
	if buffer == "siege|status" then
		Farming.sendSiegeStatus(player)
		return true
	end

	local targetId = buffer:match("^siege|fire|(%d+)$")
	if targetId then
		return Farming.fireCatapult(player, tonumber(targetId))
	end

	return baseHandleOpcode(player, buffer)
end

local baseSendBuildCatalog = Farming.sendBuildCatalog
function Farming.sendBuildCatalog(player)
	baseSendBuildCatalog(player)
	player:sendExtendedOpcode(
		Farming.OPCODE,
		string.format(
			"catalog2|wood|stair|%d|%d|%d|catapult|5609|5609|%d",
			STAIR_NORTH_ITEM_ID,
			STAIR_WEST_ITEM_ID,
			STAIR_COST,
			CATAPULT_COST
		)
	)
	Farming.sendSiegeStatus(player)
end

-- Called by farming_demolition.lua after a persisted structure is actually removed.
function Farming.onStructureDemolished(player, job)
	if not job then
		return
	end

	if job.structureType == "wall" then
		Farming.refreshSupportedPlatforms(job.playerGuid, job.position.z)
	elseif CATAPULT_TYPES[job.structureType] then
		local anchor = getCatapultAnchor(job.position, job.structureType)
		removeCatapultGroup(job.playerGuid, anchor)
		if player then
			Farming.sendSiegeStatus(player)
		end
	end
end
