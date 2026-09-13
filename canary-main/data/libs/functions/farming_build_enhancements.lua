-- Construction enhancements layered on top of the base Farming implementation.
-- Keeps the original farming system backward compatible while adding orientation,
-- non-instant sequential construction and authoritative adjacency validation.

if not Farming then
	return
end

Farming.BUILD_ORIENTATION_HORIZONTAL = 0
Farming.BUILD_ORIENTATION_VERTICAL = 1
Farming.BUILD_ADJACENT_RANGE = 1
Farming.BUILD_STEP_MS = 2000
Farming.buildBatches = Farming.buildBatches or {}
Farming.buildBatchSequence = Farming.buildBatchSequence or 0

-- Only expose orientation pairs whose horizontal/base item still matches the
-- catalogue entry. This prevents stale rotated sprites after catalogue changes.
local VERIFIED_ROTATED_VARIANTS = {
	wood = {
		door = { baseItemId = 5278, rotatedItemId = 5281 },
		window = { baseItemId = 5275, rotatedItemId = 5276 },
	},
	stone = {
		door = { baseItemId = 5278, rotatedItemId = 5281 },
		window = { baseItemId = 1465, rotatedItemId = 1471 },
	},
}

local function registerVerifiedRotatedVariants()
	for material, structures in pairs(VERIFIED_ROTATED_VARIANTS) do
		local materialCatalog = Farming.buildCatalog[material]
		if materialCatalog then
			for structureType, variant in pairs(structures) do
				local config = materialCatalog[structureType]
				if config and tonumber(config.itemId) == variant.baseItemId and variant.rotatedItemId ~= variant.baseItemId then
					config.rotatedItemId = variant.rotatedItemId
				end
			end
		end
	end
end

-- Wall ranges contain straight/corner/junction sprites and items.xml does not
-- identify the exact perpendicular pair, so wall rotation stays disabled until
-- those two IDs are visually verified.
registerVerifiedRotatedVariants()

local function buildPositionKey(position)
	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local function isAdjacentBuildPosition(player, position)
	local playerPosition = player:getPosition()
	if playerPosition.z ~= position.z then
		return false
	end

	local distance = math.max(math.abs(playerPosition.x - position.x), math.abs(playerPosition.y - position.y))
	return distance == Farming.BUILD_ADJACENT_RANGE
end

local function buildError(player, message)
	player:sendExtendedOpcode(Farming.OPCODE, "build|error|" .. tostring(message))
	player:sendCancelMessage(message)
end

local function resolveItemId(config, orientation)
	if orientation == Farming.BUILD_ORIENTATION_VERTICAL then
		if not config.rotatedItemId then
			return nil
		end
		return config.rotatedItemId
	end
	return config.itemId
end

-- v2 payload: v2|x,y,z,orientation;x,y,z,orientation
-- Legacy payloads remain accepted so older clients do not break.
local function parseBuildPayload(rawPayload)
	local raw = tostring(rawPayload or "")
	local entries = {}
	local seen = {}

	local v2Positions = raw:match("^v2|(.+)$")
	if v2Positions then
		for token in v2Positions:gmatch("[^;]+") do
			local x, y, z, orientation = token:match("^(%-?%d+),(%-?%d+),(%-?%d+),([01])$")
			if not x then
				return nil, "Invalid build position or orientation."
			end

			local position = Position(tonumber(x), tonumber(y), tonumber(z))
			local key = buildPositionKey(position)
			if not seen[key] then
				seen[key] = true
				entries[#entries + 1] = {
					position = position,
					orientation = tonumber(orientation) or Farming.BUILD_ORIENTATION_HORIZONTAL,
				}
				if #entries > Farming.BUILD_MAX_TILES then
					return nil, string.format("You can queue at most %d tiles at once.", Farming.BUILD_MAX_TILES)
				end
			end
		end
	else
		local orientation = Farming.BUILD_ORIENTATION_HORIZONTAL
		local orientationToken, positionsToken = raw:match("^([01])|(.+)$")
		if orientationToken and positionsToken then
			orientation = tonumber(orientationToken) or Farming.BUILD_ORIENTATION_HORIZONTAL
			raw = positionsToken
		end

		for token in raw:gmatch("[^;]+") do
			local x, y, z = token:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
			if not x then
				return nil, "Invalid build position."
			end

			local position = Position(tonumber(x), tonumber(y), tonumber(z))
			local key = buildPositionKey(position)
			if not seen[key] then
				seen[key] = true
				entries[#entries + 1] = { position = position, orientation = orientation }
				if #entries > Farming.BUILD_MAX_TILES then
					return nil, string.format("You can queue at most %d tiles at once.", Farming.BUILD_MAX_TILES)
				end
			end
		end
	end

	if #entries == 0 then
		return nil, "Select at least one tile to build."
	end

	return entries
end

local function validateWorldTile(position)
	local tile = Tile(position)
	if not tile or not tile:getGround() then
		return false, "One of the selected tiles is not buildable."
	end

	if tile:hasFlag(TILESTATE_HOUSE) then
		return false, "Building inside houses is disabled for now."
	end
	if tile:hasFlag(TILESTATE_PROTECTIONZONE) then
		return false, "Building in protection zones is disabled."
	end
	if tile:hasFlag(TILESTATE_FLOORCHANGE) then
		return false, "You cannot build on stairs, ramps or floor changes."
	end
	if tile:hasFlag(TILESTATE_BLOCKSOLID) then
		return false, "One of the selected tiles is already blocked."
	end
	if tile:getCreatureCount() > 0 then
		return false, "A creature is standing on one of the selected tiles."
	end
	if tile:getItemByType(ITEM_TYPE_TELEPORT) then
		return false, "You cannot build on a teleport."
	end

	local ground = tile:getGround()
	if ground and ground:getActionId() ~= 0 then
		return false, "You cannot build on a special map tile."
	end

	return true
end

local function validateBuildTile(player, position)
	if not isAdjacentBuildPosition(player, position) then
		return false, "Structures can only be planned on one of the 8 squares next to your character."
	end

	local key = buildPositionKey(position)
	if Farming.structurePositions[key] then
		return false, "There is already a player structure reserved on one of the selected tiles."
	end

	return validateWorldTile(position)
end

local function spendMaterial(player, material, amount)
	local wallet = Farming.getWallet(player)
	if (wallet[material] or 0) < amount then
		return false
	end

	if not db.query(string.format(
		"UPDATE `player_materials` SET `amount` = `amount` - %d WHERE `player_id` = %d AND `material` = '%s' AND `amount` >= %d",
		amount,
		player:getGuid(),
		material,
		amount
	)) then
		return false
	end

	Farming.sendWallet(player)
	return true
end

local function refundMaterial(playerGuid, material, amount)
	if amount <= 0 then
		return
	end

	db.query(string.format(
		"INSERT INTO `player_materials` (`player_id`, `material`, `amount`) VALUES (%d, '%s', %d) " ..
		"ON DUPLICATE KEY UPDATE `amount` = `amount` + VALUES(`amount`)",
		playerGuid,
		material,
		amount
	))
end

local function constructionEffect(x, y, z, effect)
	Position(x, y, z):sendMagicEffect(effect)
end

local function deletePersistedStructure(playerGuid, position)
	db.query(string.format(
		"DELETE FROM `player_structures` WHERE `player_id`=%d AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d",
		playerGuid,
		position.x,
		position.y,
		position.z
	))
end

local function getBatchPlayer(batch)
	local player = Player(batch.playerId)
	if player and player:getGuid() == batch.playerGuid then
		return player
	end
	return nil
end

local function finishBuildBatch(batchId)
	local batch = Farming.buildBatches[batchId]
	if not batch then
		return
	end

	local player = getBatchPlayer(batch)
	local chargedCost = batch.builtCount * batch.unitCost
	if player then
		local wallet = Farming.sendWallet(player)
		player:sendExtendedOpcode(
			Farming.OPCODE,
			string.format(
				"build|success|%s|%s|%d|%d|%d|%d",
				batch.material,
				batch.structureType,
				batch.builtCount,
				chargedCost,
				wallet[batch.material] or 0,
				batch.failedCount
			)
		)
		player:sendTextMessage(
			MESSAGE_EVENT_ADVANCE,
			string.format(
				"Built %d/%d %s structure%s for %d %s.",
				batch.builtCount,
				#batch.entries,
				batch.structureType,
				batch.builtCount == 1 and "" or "s",
				chargedCost,
				batch.material
			)
		)
	end

	Farming.buildBatches[batchId] = nil
end

local function completeBuildEntry(batchId, index)
	local batch = Farming.buildBatches[batchId]
	if not batch then
		return
	end

	local entry = batch.entries[index]
	if not entry or entry.done then
		return
	end
	entry.done = true

	local valid = validateWorldTile(entry.position)
	local created = nil
	if valid then
		created = Game.createItem(entry.itemId, 1, entry.position)
	end

	local state = "built"
	if created then
		batch.builtCount = batch.builtCount + 1
		entry.position:sendMagicEffect(CONST_ME_BLOCKHIT)
	else
		state = "failed"
		batch.failedCount = batch.failedCount + 1
		Farming.structurePositions[buildPositionKey(entry.position)] = nil
		deletePersistedStructure(batch.playerGuid, entry.position)
		refundMaterial(batch.playerGuid, batch.material, batch.unitCost)
	end

	local player = getBatchPlayer(batch)
	if player then
		player:sendExtendedOpcode(
			Farming.OPCODE,
			string.format(
				"build|piece|%d|%d|%d|%d|%d|%d|%s",
				batchId,
				index,
				entry.position.x,
				entry.position.y,
				entry.position.z,
				entry.orientation,
				state
			)
		)
	end

	batch.remaining = batch.remaining - 1
	if batch.remaining <= 0 then
		finishBuildBatch(batchId)
	end
end

-- Keep legacy catalogue packets and append orientation-aware metadata.
local baseSendBuildCatalog = Farming.sendBuildCatalog
function Farming.sendBuildCatalog(player)
	baseSendBuildCatalog(player)

	for material, structures in pairs(Farming.buildCatalog) do
		local parts = { "catalog2", material }
		for _, structureType in ipairs({ "wall", "door", "window" }) do
			local config = structures[structureType]
			if config then
				parts[#parts + 1] = structureType
				parts[#parts + 1] = tostring(config.itemId)
				parts[#parts + 1] = tostring(config.rotatedItemId or config.itemId)
				parts[#parts + 1] = tostring(config.cost)
			end
		end
		player:sendExtendedOpcode(Farming.OPCODE, table.concat(parts, "|"))
	end
end

-- Confirms an entire plan atomically, reserves its tiles and material balance,
-- then reveals one real structure every two seconds. During the delay only the
-- client-side ghost exists; construction dust is emitted before each reveal.
function Farming.confirmBuild(player, material, structureType, rawPayload)
	local materialCatalog = Farming.buildCatalog[material]
	local config = materialCatalog and materialCatalog[structureType] or nil
	if not config then
		buildError(player, "Unknown construction type.")
		return true
	end

	local entries, parseError = parseBuildPayload(rawPayload)
	if not entries then
		buildError(player, parseError)
		return true
	end

	for _, entry in ipairs(entries) do
		local valid, reason = validateBuildTile(player, entry.position)
		if not valid then
			buildError(player, reason)
			return true
		end

		entry.itemId = resolveItemId(config, entry.orientation)
		if not entry.itemId then
			buildError(player, "This construction does not have a validated rotated variant.")
			return true
		end
	end

	local totalCost = config.cost * #entries
	local wallet = Farming.getWallet(player)
	if (wallet[material] or 0) < totalCost then
		buildError(player, string.format("You need %d %s for this construction.", totalCost, material))
		return true
	end

	-- Persist first as a reservation. Runtime items are intentionally created only
	-- when their individual two-second construction step finishes.
	local values = {}
	for _, entry in ipairs(entries) do
		local position = entry.position
		values[#values + 1] = string.format(
			"(%d, '%s', '%s', %d, %d, %d, %d)",
			player:getGuid(), material, structureType, entry.itemId, position.x, position.y, position.z
		)
	end

	local insertOk = db.query(
		"INSERT INTO `player_structures` (`player_id`, `material`, `structure_type`, `item_id`, `pos_x`, `pos_y`, `pos_z`) VALUES " .. table.concat(values, ",")
	)
	if not insertOk then
		buildError(player, "Those tiles could not be reserved for construction.")
		return true
	end

	if not spendMaterial(player, material, totalCost) then
		for _, entry in ipairs(entries) do
			deletePersistedStructure(player:getGuid(), entry.position)
		end
		buildError(player, "Your material balance changed before construction was confirmed.")
		return true
	end

	for _, entry in ipairs(entries) do
		Farming.structurePositions[buildPositionKey(entry.position)] = true
	end

	Farming.buildBatchSequence = Farming.buildBatchSequence + 1
	local batchId = Farming.buildBatchSequence
	Farming.buildBatches[batchId] = {
		playerId = player:getId(),
		playerGuid = player:getGuid(),
		material = material,
		structureType = structureType,
		unitCost = config.cost,
		entries = entries,
		remaining = #entries,
		builtCount = 0,
		failedCount = 0,
	}

	player:sendExtendedOpcode(
		Farming.OPCODE,
		string.format("build|accepted|%d|%d|%d", batchId, #entries, totalCost)
	)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Construction started: %d structure%s queued.", #entries, #entries == 1 and "" or "s"))

	for index, entry in ipairs(entries) do
		local startDelay = (index - 1) * Farming.BUILD_STEP_MS
		local position = entry.position
		-- Dust while the client still shows the ghost. The real item appears only
		-- at the end of this structure's two-second step.
		addEvent(constructionEffect, startDelay + 1, position.x, position.y, position.z, CONST_ME_POFF)
		addEvent(constructionEffect, startDelay + 900, position.x, position.y, position.z, CONST_ME_POFF)
		addEvent(completeBuildEntry, startDelay + Farming.BUILD_STEP_MS, batchId, index)
	end

	return true
end