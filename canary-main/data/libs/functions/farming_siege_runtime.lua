-- Runtime integration for farming_siege.lua.
-- Keeps the existing sequential builder/demolisher untouched and reacts only
-- after their authoritative DB/runtime state has actually changed.

if not Farming then
	return
end

local STAIR_BUILD_SETTLE_MS = (Farming.BUILD_STEP_MS or 2000) + 50
local DEMOLITION_SETTLE_MS = 1600
local CATAPULT_TYPES = {
	catapult_nw = true,
	catapult_ne = true,
	catapult_sw = true,
	catapult_se = true,
}

local function positionKey(position)
	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local function parseStairEntries(rawPayload)
	local raw = tostring(rawPayload or "")
	local entries = {}
	local v2 = raw:match("^v2|(.+)$")
	if v2 then
		for token in v2:gmatch("[^;]+") do
			local x, y, z, orientation = token:match("^(%-?%d+),(%-?%d+),(%-?%d+),([01])$")
			if x then
				entries[#entries + 1] = {
					position = Position(tonumber(x), tonumber(y), tonumber(z)),
					orientation = tonumber(orientation) or 0,
				}
			end
		end
	else
		for token in raw:gmatch("[^;]+") do
			local x, y, z = token:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
			if x then
				entries[#entries + 1] = {
					position = Position(tonumber(x), tonumber(y), tonumber(z)),
					orientation = 0,
				}
			end
		end
	end
	return entries
end

local function persistedStructureAt(playerGuid, structureType, position)
	local query = db.storeQuery(string.format(
		"SELECT `id`, `item_id` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='%s' " ..
		"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
		playerGuid,
		structureType,
		position.x,
		position.y,
		position.z
	))
	if not query then
		return nil
	end
	local row = {
		id = Result.getNumber(query, "id"),
		itemId = Result.getNumber(query, "item_id"),
	}
	Result.free(query)
	return row
end

local function materializeStairPlatform(playerGuid, entry)
	local row = persistedStructureAt(playerGuid, "stair", entry.position)
	if not row then
		return
	end

	local tile = Tile(entry.position)
	if not tile or not tile:getItemById(row.itemId) then
		return
	end

	if Farming.onStructureBuilt then
		Farming.onStructureBuilt(playerGuid, "wood", "stair", entry)
	end
end

local baseConfirmBuild = Farming.confirmBuild
function Farming.confirmBuild(player, material, structureType, rawPayload)
	local stairEntries = nil
	if material == "wood" and structureType == "stair" then
		stairEntries = parseStairEntries(rawPayload)
	end

	local result = baseConfirmBuild(player, material, structureType, rawPayload)
	if result and stairEntries and #stairEntries > 0 then
		local playerGuid = player:getGuid()
		for index, entry in ipairs(stairEntries) do
			local delay = (index - 1) * (Farming.BUILD_STEP_MS or 2000) + STAIR_BUILD_SETTLE_MS
			addEvent(materializeStairPlatform, delay, playerGuid, {
				position = Position(entry.position.x, entry.position.y, entry.position.z),
				orientation = entry.orientation,
			})
		end
	end
	return result
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
		position = Position(position.x, position.y, position.z),
	}
	Result.free(query)
	return structure
end

local function persistedById(id)
	local query = db.storeQuery(string.format("SELECT `id` FROM `player_structures` WHERE `id`=%d LIMIT 1", id))
	if not query then
		return false
	end
	Result.free(query)
	return true
end

local function postDemolitionCheck(playerId, structure)
	if persistedById(structure.id) then
		return
	end

	local player = Player(playerId)
	if Farming.onStructureDemolished then
		Farming.onStructureDemolished(player, {
			structureId = structure.id,
			playerGuid = structure.playerId,
			itemId = structure.itemId,
			material = structure.material,
			structureType = structure.structureType,
			position = Position(structure.position.x, structure.position.y, structure.position.z),
		})
	elseif structure.structureType == "wall" and Farming.refreshSupportedPlatforms then
		Farming.refreshSupportedPlatforms(structure.playerId, structure.position.z)
	end
end

local baseHandlePickUse = Farming.handlePickUse
function Farming.handlePickUse(player, item, target, toPosition)
	local tracked = nil
	if target and target:isItem() and toPosition then
		tracked = getPersistedStructure(toPosition, target:getId())
	end

	local handled, consumed = baseHandlePickUse(player, item, target, toPosition)
	if tracked and tracked.playerId == player:getGuid() and (tracked.structureType == "wall" or CATAPULT_TYPES[tracked.structureType]) then
		addEvent(postDemolitionCheck, DEMOLITION_SETTLE_MS, player:getId(), tracked)
	end
	return handled, consumed
end
