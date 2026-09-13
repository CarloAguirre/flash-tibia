-- Player-built structure demolition using the same pick/farming interaction.
-- Only rows persisted in player_structures are eligible, so native map objects
-- can never be removed even when they share the same item id.

if not Farming or not Farming.handlePickUse then
	return
end

local baseHandlePickUse = Farming.handlePickUse

local function buildPositionKey(position)
	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local function isAdjacent(player, position)
	local playerPosition = player:getPosition()
	if playerPosition.z ~= position.z then
		return false
	end

	return math.max(math.abs(playerPosition.x - position.x), math.abs(playerPosition.y - position.y)) <= 1
end

local function getPersistedStructure(position, itemId)
	local query = db.storeQuery(string.format(
		"SELECT `id`, `player_id`, `item_id`, `material`, `structure_type` FROM `player_structures` " ..
		"WHERE `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d AND `item_id`=%d LIMIT 1",
		position.x,
		position.y,
		position.z,
		itemId
	))

	if not query then
		return nil
	end

	local structure = {
		id = Result.getNumber(query, "id"),
		playerId = Result.getNumber(query, "player_id"),
		itemId = Result.getNumber(query, "item_id"),
		material = Result.getString(query, "material"),
		structureType = Result.getString(query, "structure_type"),
	}
	Result.free(query)
	return structure
end

local function dismantleStructure(player, target, position, structure)
	if structure.playerId ~= player:getGuid() then
		player:sendCancelMessage("You can only dismantle structures that you built.")
		return true, true
	end

	local deleted = db.query(string.format(
		"DELETE FROM `player_structures` WHERE `id`=%d AND `player_id`=%d",
		structure.id,
		player:getGuid()
	))
	if not deleted then
		player:sendCancelMessage("The structure could not be dismantled right now.")
		return true, true
	end

	-- The target was proven to be the persisted player structure above. Removing
	-- it here cannot affect a native wall/door/window because native objects have
	-- no matching player_structures row.
	target:remove()
	Farming.structurePositions[buildPositionKey(position)] = nil

	position:sendMagicEffect(CONST_ME_POFF)
	player:sendTextMessage(
		MESSAGE_EVENT_ADVANCE,
		string.format("Dismantled your %s %s.", structure.material, structure.structureType)
	)
	return true, true
end

function Farming.handlePickUse(player, item, target, toPosition)
	local armedUntil = Farming.armed[player:getId()]
	if not armedUntil then
		return false, false
	end

	-- Preserve the exact timeout semantics of the farming interaction.
	if armedUntil < os.time() then
		Farming.armed[player:getId()] = nil
		return false, false
	end

	if target and target:isItem() and isAdjacent(player, toPosition) then
		local structure = getPersistedStructure(toPosition, target:getId())
		if structure then
			Farming.armed[player:getId()] = nil
			Farming.stop(player)
			return dismantleStructure(player, target, toPosition, structure)
		end
	end

	-- Anything that is not an actual persisted player structure keeps the original
	-- tree/rock farming behaviour untouched.
	return baseHandlePickUse(player, item, target, toPosition)
end
