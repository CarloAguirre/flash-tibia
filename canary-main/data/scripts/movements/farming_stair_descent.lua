-- Downward traversal for dynamically generated farming/building stairs.
-- The stair item itself handles going up through its native floorchange flag.
-- Generated upper platforms use item 408; when a player walks onto the specific
-- landing tile from the same upper floor, this movement sends them back down
-- beside the base of the persisted stair.

local PLATFORM_FLOOR_ITEM_ID = 408
local STAIR_NORTH_ITEM_ID = 1958
local STAIR_WEST_ITEM_ID = 7881

local function findPersistedStairForLanding(position)
	local query = db.storeQuery(string.format(
		"SELECT s.`item_id`, s.`pos_x`, s.`pos_y`, s.`pos_z` " ..
		"FROM `player_structures` p " ..
		"INNER JOIN `player_structures` s ON s.`player_id`=p.`player_id` AND s.`structure_type`='stair' " ..
		"WHERE p.`structure_type`='platform' " ..
		"AND p.`pos_x`=%d AND p.`pos_y`=%d AND p.`pos_z`=%d " ..
		"AND s.`pos_z`=%d " ..
		"AND ((s.`item_id`=%d AND s.`pos_x`=%d AND s.`pos_y`=%d) " ..
		"OR (s.`item_id`=%d AND s.`pos_x`=%d AND s.`pos_y`=%d)) " ..
		"LIMIT 1",
		position.x,
		position.y,
		position.z,
		position.z + 1,
		STAIR_NORTH_ITEM_ID,
		position.x,
		position.y + 1,
		STAIR_WEST_ITEM_ID,
		position.x + 1,
		position.y
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

local function getDescentDestination(creature, stair)
	local x = stair.position.x
	local y = stair.position.y
	local z = stair.position.z
	local candidates

	if stair.itemId == STAIR_WEST_ITEM_ID then
		-- West-facing stairs climb toward x-1; descend to the east side of the base.
		candidates = {
			Position(x + 1, y, z),
			Position(x, y - 1, z),
			Position(x, y + 1, z),
		}
	else
		-- North-facing stairs climb toward y-1; descend to the south side of the base.
		candidates = {
			Position(x, y + 1, z),
			Position(x - 1, y, z),
			Position(x + 1, y, z),
		}
	end

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
	if not player then
		return true
	end

	-- Native floorchange has just brought the player up when the previous position
	-- came from z+1. Do not immediately send them back down. Descent is triggered
	-- only when they later walk onto the landing from the same upper floor.
	if not fromPosition or fromPosition.z ~= position.z then
		return true
	end

	local stair = findPersistedStairForLanding(position)
	if not stair then
		return true
	end

	local destination = getDescentDestination(player, stair)
	if not destination then
		player:sendCancelMessage("The bottom of this stair is blocked.")
		player:teleportTo(fromPosition, true)
		return true
	end

	player:teleportTo(destination, true)
	return true
end

stairDescent:type("stepin")
stairDescent:id(PLATFORM_FLOOR_ITEM_ID)
stairDescent:register()
