-- Structural support extension for player-built upper platforms.
-- Windows are load-bearing build pieces just like walls for platform generation
-- and teardown. This layer is loaded after the base siege/runtime files so it
-- can extend their public hooks without changing native map objects.

if not Farming then
	return
end

local PLATFORM_FLOOR_ITEM_ID = 408
local DEMOLITION_SETTLE_MS = 1600

local CATAPULT_PARTS = {
	catapult_nw = { itemId = 5609, dx = 0, dy = 0 },
	catapult_ne = { itemId = 5610, dx = 1, dy = 0 },
	catapult_sw = { itemId = 5611, dx = 0, dy = 1 },
	catapult_se = { itemId = 5612, dx = 1, dy = 1 },
}

local function positionKey(position)
	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local function ownsSupportAt(playerGuid, position)
	local query = db.storeQuery(string.format(
		"SELECT `id` FROM `player_structures` WHERE `player_id`=%d " ..
		"AND `structure_type` IN ('wall','window') " ..
		"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
		playerGuid,
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

local function platformRowExists(playerGuid, position)
	local query = db.storeQuery(string.format(
		"SELECT `id` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='platform' " ..
		"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
		playerGuid,
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

	return Game.createItem(PLATFORM_FLOOR_ITEM_ID, 1, position) ~= nil
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

	Farming.structurePositions[positionKey(position)] = nil
	return true
end

local function loadOwnedSupports(playerGuid, z)
	local supports = {}
	local query = db.storeQuery(string.format(
		"SELECT `pos_x`, `pos_y`, `pos_z` FROM `player_structures` WHERE `player_id`=%d " ..
		"AND `structure_type` IN ('wall','window') AND `pos_z`=%d",
		playerGuid,
		z
	))
	if not query then
		return supports
	end

	repeat
		local position = Position(
			Result.getNumber(query, "pos_x"),
			Result.getNumber(query, "pos_y"),
			Result.getNumber(query, "pos_z")
		)
		supports[positionKey(position)] = position
	until not Result.next(query)
	Result.free(query)
	return supports
end

local function findAdjacentSupport(playerGuid, stairPosition, orientation)
	local preferred
	if orientation == 1 then
		preferred = Position(stairPosition.x - 1, stairPosition.y, stairPosition.z)
	else
		preferred = Position(stairPosition.x, stairPosition.y - 1, stairPosition.z)
	end
	if ownsSupportAt(playerGuid, preferred) then
		return preferred
	end

	local candidates = {
		Position(stairPosition.x, stairPosition.y - 1, stairPosition.z),
		Position(stairPosition.x - 1, stairPosition.y, stairPosition.z),
		Position(stairPosition.x + 1, stairPosition.y, stairPosition.z),
		Position(stairPosition.x, stairPosition.y + 1, stairPosition.z),
	}
	for _, candidate in ipairs(candidates) do
		if ownsSupportAt(playerGuid, candidate) then
			return candidate
		end
	end
	return nil
end

local function collectConnectedSupports(supports, seed)
	local seedKey = positionKey(seed)
	if not supports[seedKey] then
		return {}
	end

	local queue = { supports[seedKey] }
	local queued = { [seedKey] = true }
	local connected = {}
	local cursor = 1

	while cursor <= #queue and #connected < (Farming.BUILD_MAX_TILES or 40) do
		local current = queue[cursor]
		cursor = cursor + 1
		connected[#connected + 1] = current

		for dx = -1, 1 do
			for dy = -1, 1 do
				if not (dx == 0 and dy == 0) then
					local neighbor = Position(current.x + dx, current.y + dy, current.z)
					local key = positionKey(neighbor)
					if supports[key] and not queued[key] then
						queued[key] = true
						queue[#queue + 1] = supports[key]
					end
				end
			end
		end
	end

	return connected
end

local function generatePlatformIncludingWindows(playerGuid, stairPosition, orientation)
	local support = findAdjacentSupport(playerGuid, stairPosition, orientation or 0)
	if not support then
		return
	end

	local supports = loadOwnedSupports(playerGuid, stairPosition.z)
	for _, supportPosition in ipairs(collectConnectedSupports(supports, support)) do
		persistPlatformTile(
			playerGuid,
			Position(supportPosition.x, supportPosition.y, supportPosition.z - 1)
		)
	end
end

local function loadPlatformRows(playerGuid, platformZ)
	local rows = {}
	local query = db.storeQuery(string.format(
		"SELECT `id`, `pos_x`, `pos_y`, `pos_z` FROM `player_structures` " ..
		"WHERE `player_id`=%d AND `structure_type`='platform' AND `pos_z`=%d ORDER BY `id`",
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
		if ownsSupportAt(playerGuid, lower) then
			return true
		end
	end
	return false
end

local function getCatapultAnchor(position, structureType)
	local part = CATAPULT_PARTS[structureType]
	if not part then
		return nil
	end
	return Position(position.x - part.dx, position.y - part.dy, position.z)
end

local function removeCatapultAtAnchor(playerGuid, anchor)
	for structureType, part in pairs(CATAPULT_PARTS) do
		local position = Position(anchor.x + part.dx, anchor.y + part.dy, anchor.z)
		local tile = Tile(position)
		local item = tile and tile:getItemById(part.itemId) or nil
		if item then
			item:remove()
		end
		db.query(string.format(
			"DELETE FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='%s' " ..
			"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d",
			playerGuid,
			structureType,
			position.x,
			position.y,
			position.z
		))
		Farming.structurePositions[positionKey(position)] = nil
	end
end

local function removeUnsupportedComponent(playerGuid, component)
	local anchors = {}
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
			if anchor then
				anchors[positionKey(anchor)] = anchor
			end
		end
	end
	for _, anchor in pairs(anchors) do
		removeCatapultAtAnchor(playerGuid, anchor)
	end

	for _, row in ipairs(component) do
		local tile = Tile(row.position)
		if tile then
			local creatures = tile:getCreatures()
			if creatures then
				local lower = Position(row.position.x, row.position.y, row.position.z + 1)
				for _, creature in ipairs(creatures) do
					creature:teleportTo(lower, true)
				end
			end
			local ground = tile:getGround()
			if ground and ground:getId() == PLATFORM_FLOOR_ITEM_ID then
				ground:remove()
			end
		end
		db.query(string.format("DELETE FROM `player_structures` WHERE `id`=%d AND `player_id`=%d", row.id, playerGuid))
		Farming.structurePositions[positionKey(row.position)] = nil
	end
end

-- Replace the base refresh so both walls and windows can keep an upper platform
-- alive. A component disappears only when none of its tiles has a structural
-- support beneath it.
function Farming.refreshSupportedPlatforms(playerGuid, lowerZ)
	local platformZ = lowerZ - 1
	if platformZ < 0 then
		return
	end
	local rows = loadPlatformRows(playerGuid, platformZ)
	for _, component in ipairs(connectedPlatformComponents(rows)) do
		if not componentHasSupport(playerGuid, component) then
			removeUnsupportedComponent(playerGuid, component)
		end
	end
end

local baseOnStructureBuilt = Farming.onStructureBuilt
function Farming.onStructureBuilt(playerGuid, material, structureType, entry)
	if baseOnStructureBuilt then
		baseOnStructureBuilt(playerGuid, material, structureType, entry)
	end
	if material == "wood" and structureType == "stair" and entry and entry.position then
		generatePlatformIncludingWindows(playerGuid, entry.position, entry.orientation or 0)
	end
end

local baseOnStructureDemolished = Farming.onStructureDemolished
function Farming.onStructureDemolished(player, job)
	if baseOnStructureDemolished then
		baseOnStructureDemolished(player, job)
	end
	if job and job.structureType == "window" then
		Farming.refreshSupportedPlatforms(job.playerGuid, job.position.z)
	end
end

local function getOwnedWindow(position, itemId, playerGuid)
	local query = db.storeQuery(string.format(
		"SELECT `id` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='window' AND `item_id`=%d " ..
		"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
		playerGuid,
		itemId,
		position.x,
		position.y,
		position.z
	))
	if not query then
		return nil
	end
	local id = Result.getNumber(query, "id")
	Result.free(query)
	return id
end

local function refreshAfterWindowDemolition(playerGuid, lowerZ, structureId)
	local query = db.storeQuery(string.format("SELECT `id` FROM `player_structures` WHERE `id`=%d LIMIT 1", structureId))
	if query then
		Result.free(query)
		return
	end
	Farming.refreshSupportedPlatforms(playerGuid, lowerZ)
end

-- farming_siege_runtime historically tracked wall demolition only. Extend the
-- same delayed post-demolition refresh to windows so removing a load-bearing
-- window can invalidate an unsupported upper component as well.
local baseHandlePickUse = Farming.handlePickUse
function Farming.handlePickUse(player, item, target, toPosition)
	local trackedWindowId = nil
	local playerGuid = player:getGuid()
	if target and target:isItem() and toPosition then
		trackedWindowId = getOwnedWindow(toPosition, target:getId(), playerGuid)
	end

	local handled, consumed = baseHandlePickUse(player, item, target, toPosition)
	if trackedWindowId then
		addEvent(refreshAfterWindowDemolition, DEMOLITION_SETTLE_MS, playerGuid, toPosition.z, trackedWindowId)
	end
	return handled, consumed
end
