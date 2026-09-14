-- Downward traversal for dynamically generated farming/building stairs.
-- Native stair items handle ascent. We learn the exact upper landing used by
-- the engine, then descend only when the player deliberately walks from that
-- landing toward the square directly above the persisted stair base.

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

local function platformRowExists(playerGuid, position)
	local query = db.storeQuery(string.format(
		"SELECT `id` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='platform' " ..
		"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
		playerGuid, position.x, position.y, position.z
	))
	if not query then
		return false
	end
	Result.free(query)
	return true
end

local function ensureReturnTrigger(playerGuid, stair, upperZ)
	local position = Position(stair.position.x, stair.position.y, upperZ)
	local tile = Tile(position)
	if not tile then
		Game.createTile(position, true)
		tile = Tile(position)
	end
	if not tile then
		return nil
	end

	local ground = tile:getGround()
	if ground then
		if ground:getId() ~= PLATFORM_FLOOR_ITEM_ID then
			return nil
		end
	elseif not Game.createItem(PLATFORM_FLOOR_ITEM_ID, 1, position) then
		return nil
	end

	if not platformRowExists(playerGuid, position) then
		local inserted = db.query(string.format(
			"INSERT INTO `player_structures` (`player_id`,`material`,`structure_type`,`item_id`,`pos_x`,`pos_y`,`pos_z`) " ..
			"VALUES (%d,'wood','platform',%d,%d,%d,%d)",
			playerGuid,
			PLATFORM_FLOOR_ITEM_ID,
			position.x,
			position.y,
			position.z
		))
		if not inserted then
			return nil
		end
	end

	-- A platform tile is walkable support. It must not reserve the construction
	-- slot even though it is persisted in player_structures.
	if Farming.structurePositions then
		Farming.structurePositions[positionKey(position)] = nil
	end
	return position
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

	-- Ascending: learn the landing selected by the native floorchange and ensure
	-- there is one walkable upper square directly above the lower stair. Walking
	-- onto that square from the learned landing is the deliberate "walk down the
	-- stairs" action; merely standing on the landing never descends.
	if fromPosition.z == position.z + 1 then
		local stair = findNearbyPersistedStair(ownerGuid, fromPosition.z, fromPosition)
		if stair then
			local returnTrigger = ensureReturnTrigger(ownerGuid, stair, position.z)
			Farming.stairLandingCache[playerGuid] = {
				landingKey = positionKey(position),
				returnKey = returnTrigger and positionKey(returnTrigger) or nil,
				ownerGuid = ownerGuid,
				stair = stair,
				down = Position(fromPosition.x, fromPosition.y, fromPosition.z),
			}
		end
		return true
	end

	-- Same-floor movement only descends when it starts on the learned landing and
	-- ends on the square directly above the stair base. All other upper-platform
	-- walking remains completely ordinary.
	if fromPosition.z ~= position.z then
		return true
	end

	local learned = Farming.stairLandingCache[playerGuid]
	if not learned or learned.ownerGuid ~= ownerGuid then
		return true
	end
	if positionKey(fromPosition) ~= learned.landingKey then
		return true
	end
	if not learned.returnKey or positionKey(position) ~= learned.returnKey then
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
