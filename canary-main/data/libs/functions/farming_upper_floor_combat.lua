-- Marks runtime-generated farming platforms so the Canary combat layer can
-- distinguish them from ordinary map floors. The marker is an item custom
-- attribute, so normal action-id based construction validation remains intact.

if not Farming then
	return
end

local PLATFORM_ITEM_ID = 408
local PLATFORM_ATTRIBUTE = "farmingUpperFloor"

local function markPlatformGround(position)
	local tile = Tile(position)
	local ground = tile and tile:getGround() or nil
	if not ground or ground:getId() ~= PLATFORM_ITEM_ID then
		return false
	end

	ground:setCustomAttribute(PLATFORM_ATTRIBUTE, 1)
	return true
end

local function markOwnedPlatforms(playerGuid)
	local query = db.storeQuery(string.format(
		"SELECT `pos_x`,`pos_y`,`pos_z` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='platform'",
		playerGuid
	))
	if not query then
		return 0
	end

	local marked = 0
	repeat
		local position = Position(
			Result.getNumber(query, "pos_x"),
			Result.getNumber(query, "pos_y"),
			Result.getNumber(query, "pos_z")
		)
		if markPlatformGround(position) then
			marked = marked + 1
		end
	until not Result.next(query)
	Result.free(query)
	return marked
end

-- Stairs generate their supported upper platform through the existing build hook.
-- Mark it only after the whole hook chain has finished generating/trimming tiles.
local baseOnStructureBuilt = Farming.onStructureBuilt
function Farming.onStructureBuilt(playerGuid, material, structureType, entry)
	if baseOnStructureBuilt then
		baseOnStructureBuilt(playerGuid, material, structureType, entry)
	end

	if material == "wood" and structureType == "stair" then
		markOwnedPlatforms(playerGuid)
	end
end

-- Manually placed Wood Floor is created synchronously by farming_floor_build.lua.
-- Re-scan the owner's platform rows after confirmation so the new tile receives
-- the same combat marker as automatically generated floor.
local baseConfirmBuild = Farming.confirmBuild
function Farming.confirmBuild(player, material, structureType, rawPayload)
	local result = baseConfirmBuild(player, material, structureType, rawPayload)
	if material == "wood" and structureType == "floor" then
		markOwnedPlatforms(player:getGuid())
	end
	return result
end

-- Keep the marker self-healing when the client asks for upper-floor status. This
-- covers platform refresh/prune paths that can recreate item 408 during a session.
local baseSendSiegeStatus = Farming.sendSiegeStatus
if baseSendSiegeStatus then
	function Farming.sendSiegeStatus(player)
		markOwnedPlatforms(player:getGuid())
		return baseSendSiegeStatus(player)
	end
end
