-- Downward traversal for dynamically generated farming/building stairs.
-- Native stair items handle the ascent. The first time a player arrives on an
-- upper platform through one of those stairs, we learn the actual landing tile
-- used by the engine and remember the lower position they came from. Returning
-- to that landing from the same upper floor then sends the player back down.

local PLATFORM_FLOOR_ITEM_ID = 408
local STAIR_SEARCH_RADIUS = 2

Farming = Farming or {}
Farming.stairLandingCache = Farming.stairLandingCache or {}

local function positionKey(position)
	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local function getPlatformOwner(position)
	local query = db.storeQuery(string.format(
		"SELECT `player_id` FROM `player_structures` WHERE `structure_type`='platform' " ..
		"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
		position.x,
		position.y,
		position.z
	))
	if not query then
		return nil
	end
	local playerGuid = Result.getNumber(query, "player_id")
	Result.free(query)
	return playerGuid
end

local function findNearbyPersistedStair(playerGuid, lowerZ, aroundPosition)
	local minX = aroundPosition.x - STAIR_SEARCH_RADIUS
	local maxX = aroundPosition.x + STAIR_SEARCH_RADIUS
	local minY = aroundPosition.y - STAIR_SEARCH_RADIUS
	local maxY = aroundPosition.y + STAIR_SEARCH_RADIUS
	local query = db.storeQuery(string.format(
		"SELECT `item_id`, `pos_x`, `pos_y`, `pos_z` FROM `player_structures` " ..
		"WHERE `player_id`=%d AND `structure_type`='stair' AND `pos_z`=%d " ..
		"AND `pos_x` BETWEEN %d AND %d AND `pos_y` BETWEEN %d AND %d " ..
		"ORDER BY (ABS(`pos_x`-%d) + ABS(`pos_y`-%d)) ASC LIMIT 1",
		playerGuid,
		lowerZ,
		minX,
		maxX,
		minY,
		maxY,
		aroundPosition.x,
		aroundPosition.y
	))
	if not query then
		return nil
	end
	local stair = {
		itemId = Result.getNumber(query, "item_id"),
		position = Position(
			Result.getNumber(query, "pos_x"),
			Result.getNumber(query, "pos_y"),
			Result.getNumber(query, "pos_z")
		),
	}
	Result.free(query)
	return stair
end

local function canEnter(creature, position)
	local tile = Tile(position)
	if not tile then
		return false
	end
	return tile:queryAdd(creature) == RETURNVALUE_NOERROR
end

local function findFallbackDescent(creature, upperPosition, stair)
	-- Prefer the same x/y one floor below. If that is occupied by the supporting
	-- wall, fall back to free cardinal squares around the stair base.
	local projected = Position(upperPosition.x, upperPosition.y, upperPosition.z + 1)
	if canEnter(creature, projected) then
		return projected
	end

	local x = stair.position.x
	local y = stair.position.y
	local z = stair.position.z
	local candidates = {
		Position(x, y + 1, z),
		Position(x + 1, y, z),
		Position(x, y - 1, z),
		Position(x - 1, y, z),
	}
	for _, candidate in ipairs(candidates) do
		if canEnter(creature, candidate) then
			return candidate
		end
	end
	return nil
end

local stairDescent = MoveEvent()

function stairDescent.onStepIn(creature, item, position, fromPosition)
	local player = creature:getPlayer()
	if not player or not fromPosition then
		return true
	end

	local ownerGuid = getPlatformOwner(position)
	if not ownerGuid then
		return true
	end

	local key = positionKey(position)

	-- Learn the *actual* landing chosen by the native floorchange. This avoids
	-- hard-coding assumptions about how each stair sprite offsets x/y while
	-- climbing. The previous lower-floor square is always a valid return target.
	if fromPosition.z == position.z + 1 then
		local stair = findNearbyPersistedStair(ownerGuid, fromPosition.z, fromPosition)
		if stair then
			Farming.stairLandingCache[key] = {
				playerGuid = ownerGuid,
				stair = stair,
				down = Position(fromPosition.x, fromPosition.y, fromPosition.z),
			}
		end
		return true
	end

	-- Only descend when the player deliberately walks back onto the landing from
	-- the same upper floor. This prevents an immediate up/down bounce on ascent.
	if fromPosition.z ~= position.z then
		return true
	end

	local landing = Farming.stairLandingCache[key]
	local destination = nil
	if landing and landing.playerGuid == ownerGuid and canEnter(player, landing.down) then
		destination = landing.down
	else
		-- Server restarts clear the learned cache. Recover gracefully by locating
		-- the nearest persisted stair belonging to the same platform owner.
		local stair = findNearbyPersistedStair(ownerGuid, position.z + 1, position)
		if stair then
			destination = findFallbackDescent(player, position, stair)
		end
	end

	if not destination then
		return true
	end

	player:teleportTo(destination, true)
	return true
end

stairDescent:type("stepin")
stairDescent:id(PLATFORM_FLOOR_ITEM_ID)
stairDescent:register()
