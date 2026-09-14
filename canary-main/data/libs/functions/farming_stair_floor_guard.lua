-- Keep the upper-floor stair shaft open.
-- The enclosed-floor generator may legitimately classify the stair's own X/Y as
-- interior. That square must stay empty on Z-1 so the stair sprite/opening is not
-- covered by a generated platform tile. The actual landing square remains intact.

if not Farming then
	return
end

local PLATFORM_FLOOR_ITEM_ID = 408

local function positionKey(position)
	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local function clearStairShaft(playerGuid, stairPosition)
	if not stairPosition or stairPosition.z <= 0 then
		return false
	end

	local upperPosition = Position(stairPosition.x, stairPosition.y, stairPosition.z - 1)
	local query = db.storeQuery(string.format(
		"SELECT `id` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='platform' " ..
		"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
		playerGuid,
		upperPosition.x,
		upperPosition.y,
		upperPosition.z
	))
	if not query then
		return false
	end

	local rowId = Result.getNumber(query, "id")
	Result.free(query)

	local tile = Tile(upperPosition)
	local ground = tile and tile:getGround() or nil
	if ground and ground:getId() == PLATFORM_FLOOR_ITEM_ID then
		ground:remove()
	end

	db.query(string.format(
		"DELETE FROM `player_structures` WHERE `id`=%d AND `player_id`=%d",
		rowId,
		playerGuid
	))
	Farming.structurePositions[positionKey(upperPosition)] = nil
	return true
end

local baseOnStructureBuilt = Farming.onStructureBuilt
function Farming.onStructureBuilt(playerGuid, material, structureType, entry)
	if baseOnStructureBuilt then
		baseOnStructureBuilt(playerGuid, material, structureType, entry)
	end

	if material == "wood" and structureType == "stair" and entry and entry.position then
		clearStairShaft(playerGuid, entry.position)
	end
end
