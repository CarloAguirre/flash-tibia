-- Re-apply runtime occupancy for persisted catapult overlays after the platform
-- restore layers clear their own walkable reservations.

if not Farming then
	return
end

local function positionKey(position)
	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local baseRestoreStructures = Farming.restoreStructures
function Farming.restoreStructures()
	local result = baseRestoreStructures()

	local query = db.storeQuery(
		"SELECT `pos_x`,`pos_y`,`pos_z` FROM `player_structures` " ..
		"WHERE `structure_type` IN ('catapult_nw','catapult_ne','catapult_sw','catapult_se') ORDER BY `id`"
	)
	if not query then
		return result
	end

	repeat
		local position = Position(
			Result.getNumber(query, "pos_x"),
			Result.getNumber(query, "pos_y"),
			Result.getNumber(query, "pos_z")
		)
		Farming.structurePositions[positionKey(position)] = true
	until not Result.next(query)
	Result.free(query)

	return result
end
