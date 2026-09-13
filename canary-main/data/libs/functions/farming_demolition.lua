-- Player-built structure demolition using the same pick/farming interaction.
-- Only rows persisted in player_structures are eligible, so native map objects
-- can never be removed even when they share the same item id.

if not Farming or not Farming.handlePickUse then
	return
end

local baseHandlePickUse = Farming.handlePickUse
local DEMOLITION_DELAY_MS = 1500
local DEMOLITION_EFFECT_MID_MS = 750

Farming.demolitionJobs = Farming.demolitionJobs or {}

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
		"WHERE `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d AND `item_id`=%d AND `structure_type`<>'platform' LIMIT 1",
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

local function structureStillPersisted(job)
	local query = db.storeQuery(string.format(
		"SELECT `id` FROM `player_structures` WHERE `id`=%d AND `player_id`=%d AND `item_id`=%d " ..
		"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
		job.structureId,
		job.playerGuid,
		job.itemId,
		job.position.x,
		job.position.y,
		job.position.z
	))
	if not query then
		return false
	end
	Result.free(query)
	return true
end

local function emitDemolitionEffect(structureId)
	local job = Farming.demolitionJobs[structureId]
	if not job then
		return
	end

	local player = Player(job.playerId)
	if not player or player:getGuid() ~= job.playerGuid or not isAdjacent(player, job.position) then
		return
	end

	job.position:sendMagicEffect(CONST_ME_POFF)
end

local function completeDemolition(structureId)
	local job = Farming.demolitionJobs[structureId]
	if not job then
		return
	end
	Farming.demolitionJobs[structureId] = nil

	local player = Player(job.playerId)
	if not player or player:getGuid() ~= job.playerGuid then
		return
	end

	if not isAdjacent(player, job.position) then
		player:sendCancelMessage("You moved too far away before dismantling finished.")
		return
	end

	if not structureStillPersisted(job) then
		player:sendCancelMessage("That structure is no longer available to dismantle.")
		return
	end

	local tile = Tile(job.position)
	local target = tile and tile:getItemById(job.itemId) or nil
	if not target then
		player:sendCancelMessage("That structure is no longer available to dismantle.")
		return
	end

	local deleted = db.query(string.format(
		"DELETE FROM `player_structures` WHERE `id`=%d AND `player_id`=%d",
		job.structureId,
		job.playerGuid
	))
	if not deleted then
		player:sendCancelMessage("The structure could not be dismantled right now.")
		return
	end

	-- The target was proven to be the persisted player structure above. Removing
	-- it here cannot affect a native wall/door/window because native objects have
	-- no matching player_structures row. Generated platform floors are excluded
	-- from direct pick demolition and are removed only by support reconciliation.
	target:remove()
	Farming.structurePositions[buildPositionKey(job.position)] = nil

	job.position:sendMagicEffect(CONST_ME_BLOCKHIT)
	job.position:sendMagicEffect(CONST_ME_POFF)
	player:sendTextMessage(
		MESSAGE_EVENT_ADVANCE,
		string.format("Dismantled your %s %s.", job.material, job.structureType)
	)
end

local function startDemolition(player, position, structure)
	if structure.playerId ~= player:getGuid() then
		player:sendCancelMessage("You can only dismantle structures that you built.")
		return true, true
	end

	if Farming.demolitionJobs[structure.id] then
		player:sendCancelMessage("That structure is already being dismantled.")
		return true, true
	end

	local job = {
		structureId = structure.id,
		playerId = player:getId(),
		playerGuid = player:getGuid(),
		itemId = structure.itemId,
		material = structure.material,
		structureType = structure.structureType,
		position = Position(position.x, position.y, position.z),
	}
	Farming.demolitionJobs[structure.id] = job

	player:sendTextMessage(
		MESSAGE_EVENT_ADVANCE,
		string.format("Dismantling your %s %s...", structure.material, structure.structureType)
	)

	-- Mirror the construction feedback: dust while the structure remains visible,
	-- then remove it only after the full 1.5 second dismantling duration.
	addEvent(emitDemolitionEffect, 1, structure.id)
	addEvent(emitDemolitionEffect, DEMOLITION_EFFECT_MID_MS, structure.id)
	addEvent(completeDemolition, DEMOLITION_DELAY_MS, structure.id)
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
			return startDemolition(player, toPosition, structure)
		end
	end

	-- Anything that is not an actual persisted player structure keeps the original
	-- tree/rock farming behaviour untouched.
	return baseHandlePickUse(player, item, target, toPosition)
end
