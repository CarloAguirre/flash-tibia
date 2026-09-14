-- Downward traversal for dynamically generated farming/building stairs.
-- Native stair items handle ascent. We learn the exact upper landing used by
-- the engine for each player and only that tile can trigger the return trip.

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
		position.x, position.y, position.z
	))
	if not query then
		return nil
	end
	local playerGuid = Result.getNumber(query, "player_id")
	Result.free(query)
	return playerGuid
end

local function findNearbyPersistedStair(playerGuid, lowerZ, aroundPosition)
	local query = db.storeQuery(string.format(
		"SELECT `item_id`, `pos_x`, `pos_y`, `pos_z` FROM `player_structures` " ..
		"WHERE `player_id`=%d AND `structure_type`='stair' AND `pos_z`=%d " ..
		"AND `pos_x` BETWEEN %d AND %d AND `pos_y` BETWEEN %d AND %d " ..
		"ORDER BY (ABS(`pos_x`-%d) + ABS(`pos_y`-%d)) ASC LIMIT 1",
		playerGuid,
		lowerZ,
		aroundPosition.x - STAIR_SEARCH_RADIUS,
		aroundPosition.x + STAIR_SEARCH_RADIUS,
		aroundPosition.y - STAIR_SEARCH_RADIUS,
		aroundPosition.y + STAIR_SEARCH_RADIUS,
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

local function findSafeLowerDestination(creature, learnedDown, stair)
	if learnedDown and canEnter(creature, learnedDown) then
		return learnedDown
	end

	if not stair then
		return nil
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

	local playerGuid = player:getGuid()

	-- Ascending: learn the exact landing tile chosen by the native floorchange.
	-- Nothing else on the upper platform becomes a descent trigger.
	if fromPosition.z == position.z + 1 then
		local stair = findNearbyPersistedStair(ownerGuid, fromPosition.z, fromPosition)
		if stair then
			Farming.stairLandingCache[playerGuid] = {
				landingKey = positionKey(position),
				ownerGuid = ownerGuid,
				stair = stair,
				down = Position(fromPosition.x, fromPosition.y, fromPosition.z),
			}
		end
		return true
	end

	-- Ordinary movement across the upper floor must never send the player down.
	if fromPosition.z ~= position.z then
		return true
	end

	local learned = Farming.stairLandingCache[playerGuid]
	if not learned or learned.ownerGuid ~= ownerGuid or learned.landingKey ~= positionKey(position) then
		return true
	end

	local destination = findSafeLowerDestination(player, learned.down, learned.stair)
	if not destination then
		player:sendCancelMessage("The bottom of this stair is blocked.")
		return true
	end

	Farming.stairLandingCache[playerGuid] = nil
	player:teleportTo(destination, true)
	return true
end

stairDescent:type("stepin")
stairDescent:id(PLATFORM_FLOOR_ITEM_ID)
stairDescent:register()
