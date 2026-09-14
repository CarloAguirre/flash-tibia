-- Fill the interior enclosed by player-built wall/window/door supports.
-- The existing siege support layer creates platform tiles above the perimeter;
-- this extension treats that perimeter as a structural contour and fills the
-- enclosed second-floor surface as well.

if not Farming then
	return
end

local PLATFORM_FLOOR_ITEM_ID = 408
local STAIR_WEST_ITEM_ID = 7881
local MAX_FILL_AREA = 256

local function positionKey(position)
	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local function planarKey(x, y)
	return string.format("%d:%d", x, y)
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
		"AND `structure_type` IN ('wall','window','door') AND `pos_z`=%d",
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

local function ownsSupportAt(playerGuid, position)
	local query = db.storeQuery(string.format(
		"SELECT `id` FROM `player_structures` WHERE `player_id`=%d " ..
		"AND `structure_type` IN ('wall','window','door') " ..
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

local function enclosedInterior(connected)
	if #connected < 4 then
		return {}
	end

	local supportSet = {}
	local minX, maxX = connected[1].x, connected[1].x
	local minY, maxY = connected[1].y, connected[1].y
	for _, position in ipairs(connected) do
		supportSet[planarKey(position.x, position.y)] = true
		minX = math.min(minX, position.x)
		maxX = math.max(maxX, position.x)
		minY = math.min(minY, position.y)
		maxY = math.max(maxY, position.y)
	end

	local width = maxX - minX + 1
	local height = maxY - minY + 1
	if width * height > MAX_FILL_AREA then
		return {}
	end

	local outerMinX, outerMaxX = minX - 1, maxX + 1
	local outerMinY, outerMaxY = minY - 1, maxY + 1
	local outside = {}
	local queue = { { x = outerMinX, y = outerMinY } }
	outside[planarKey(outerMinX, outerMinY)] = true
	local cursor = 1

	-- Use cardinal connectivity only. With an 8-neighbour flood fill the exterior
	-- can leak diagonally through one-tile wall corners and incorrectly classify a
	-- perfectly enclosed room as open.
	local directions = {
		{ 0, -1 },
		{ -1, 0 }, { 1, 0 },
		{ 0, 1 },
	}

	while cursor <= #queue do
		local current = queue[cursor]
		cursor = cursor + 1
		for _, direction in ipairs(directions) do
			local nx = current.x + direction[1]
			local ny = current.y + direction[2]
			if nx >= outerMinX and nx <= outerMaxX and ny >= outerMinY and ny <= outerMaxY then
				local key = planarKey(nx, ny)
				if not supportSet[key] and not outside[key] then
					outside[key] = true
					queue[#queue + 1] = { x = nx, y = ny }
				end
			end
		end
	end

	local interior = {}
	for x = minX, maxX do
		for y = minY, maxY do
			local key = planarKey(x, y)
			if not supportSet[key] and not outside[key] then
				interior[#interior + 1] = { x = x, y = y }
			end
		end
	end
	return interior
end

local function fillEnclosedPlatform(playerGuid, stairPosition, orientation)
	local support = findAdjacentSupport(playerGuid, stairPosition, orientation or 0)
	if not support then
		return 0
	end

	local supports = loadOwnedSupports(playerGuid, stairPosition.z)
	local connected = collectConnectedSupports(supports, support)
	if #connected == 0 then
		return 0
	end

	local created = 0
	local platformZ = stairPosition.z - 1
	for _, supportPosition in ipairs(connected) do
		if persistPlatformTile(playerGuid, Position(supportPosition.x, supportPosition.y, platformZ)) then
			created = created + 1
		end
	end
	for _, cell in ipairs(enclosedInterior(connected)) do
		if persistPlatformTile(playerGuid, Position(cell.x, cell.y, platformZ)) then
			created = created + 1
		end
	end
	return created
end

local baseOnStructureBuilt = Farming.onStructureBuilt
function Farming.onStructureBuilt(playerGuid, material, structureType, entry)
	if baseOnStructureBuilt then
		baseOnStructureBuilt(playerGuid, material, structureType, entry)
	end
	if material == "wood" and structureType == "stair" and entry and entry.position then
		fillEnclosedPlatform(playerGuid, entry.position, entry.orientation or 0)
	end
end

local function rebuildExistingStairPlatforms()
	local query = db.storeQuery(
		"SELECT `player_id`, `item_id`, `pos_x`, `pos_y`, `pos_z` FROM `player_structures` WHERE `structure_type`='stair' ORDER BY `id`"
	)
	if not query then
		return
	end

	repeat
		local playerGuid = Result.getNumber(query, "player_id")
		local itemId = Result.getNumber(query, "item_id")
		local position = Position(
			Result.getNumber(query, "pos_x"),
			Result.getNumber(query, "pos_y"),
			Result.getNumber(query, "pos_z")
		)
		fillEnclosedPlatform(playerGuid, position, itemId == STAIR_WEST_ITEM_ID and 1 or 0)
	until not Result.next(query)
	Result.free(query)
end

local baseRestoreStructures = Farming.restoreStructures
function Farming.restoreStructures()
	local result = baseRestoreStructures()
	rebuildExistingStairPlatforms()
	return result
end
