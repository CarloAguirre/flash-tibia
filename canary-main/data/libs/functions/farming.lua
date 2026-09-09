Farming = Farming or {}

Farming.OPCODE = 217
Farming.PICK_ITEM_ID = 3456
Farming.ARM_TIMEOUT_SECONDS = 10
Farming.HIT_INTERVAL_MS = 1000
Farming.REWARD_HITS_MIN = 1
Farming.REWARD_HITS_MAX = 3
Farming.RESOURCE_HITS_MIN = 8
Farming.RESOURCE_HITS_MAX = 12
Farming.BUILD_MAX_TILES = 40
Farming.BUILD_MAX_RANGE = 7

Farming.armed = Farming.armed or {}
Farming.sessions = Farming.sessions or {}
Farming.resourceStates = Farming.resourceStates or {}
Farming.structurePositions = Farming.structurePositions or {}
Farming.sessionSequence = Farming.sessionSequence or 0

-- First construction catalogue. IDs are real items from data/items/items.xml.
-- The server owns prices and item IDs; the client only receives them for preview/UI.
Farming.buildCatalog = {
	wood = {
		wall = { itemId = 5260, cost = 5, label = "Wood Wall" },
		door = { itemId = 5278, cost = 8, label = "Wood Door" },
		window = { itemId = 5275, cost = 6, label = "Wood Window" },
	},
	stone = {
		wall = { itemId = 1450, cost = 6, label = "Stone Wall" },
		door = { itemId = 5278, cost = 10, label = "Stone Door" },
		window = { itemId = 1465, cost = 8, label = "Stone Window" },
	},
}

-- Explicit overrides are intentionally small for the MVP. Most ordinary world
-- resources are detected by their item name; special/quest objects can be
-- blacklisted here as we catalogue the global map.
Farming.resourceOverrides = {
	[3699] = "wood", -- blueberry bush
}

Farming.resourceBlacklist = {
	-- Add quest/special world objects here when they must never be farmable.
}

local blockedNameFragments = {
	"wall",
	"door",
	"window",
	"floor",
	"tile",
	"statue",
	"pillar",
	"column",
	"bridge",
	"altar",
	"tomb",
	"coffin",
	"chest",
	"table",
	"stair",
	"gate",
	"roof",
}

local function containsPlain(value, fragment)
	return value:find(fragment, 1, true) ~= nil
end

local function positionKey(position, itemId)
	return string.format("%d:%d:%d:%d", position.x, position.y, position.z, itemId)
end

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

local function isWithinBuildRange(player, position)
	local playerPosition = player:getPosition()
	if playerPosition.z ~= position.z then
		return false
	end

	return math.max(math.abs(playerPosition.x - position.x), math.abs(playerPosition.y - position.y)) <= Farming.BUILD_MAX_RANGE
end

local function getResourceState(key)
	local state = Farming.resourceStates[key]
	if not state then
		state = {
			remainingHits = math.random(Farming.RESOURCE_HITS_MIN, Farming.RESOURCE_HITS_MAX),
		}
		Farming.resourceStates[key] = state
	end

	return state
end

local function buildError(player, message)
	player:sendExtendedOpcode(Farming.OPCODE, "build|error|" .. tostring(message))
	player:sendCancelMessage(message)
end

function Farming.classifyItem(item)
	if not item or not item:isItem() then
		return nil
	end

	local itemId = item:getId()
	if Farming.resourceBlacklist[itemId] then
		return nil
	end

	-- Never dynamically remove action-bound map objects. This protects a large
	-- class of quest/special objects while we catalogue farmable world resources.
	if item:getActionId() ~= 0 then
		return nil
	end

	local override = Farming.resourceOverrides[itemId]
	if override then
		return override
	end

	local itemType = ItemType(itemId)
	if not itemType or itemType:getId() == 0 or itemType:isMovable() then
		return nil
	end

	local name = (itemType:getName() or ""):lower()
	if name == "" then
		return nil
	end

	for _, fragment in ipairs(blockedNameFragments) do
		if containsPlain(name, fragment) then
			return nil
		end
	end

	if containsPlain(name, "tree") or containsPlain(name, "bush") or containsPlain(name, "shrub") then
		return "wood"
	end

	if name == "stone" or containsPlain(name, "rock") or containsPlain(name, "boulder") or containsPlain(name, "stone pile") or containsPlain(name, "stone heap") then
		return "stone"
	end

	return nil
end

function Farming.getWallet(player)
	local wallet = {
		wood = 0,
		stone = 0,
	}

	local query = db.storeQuery(string.format(
		"SELECT `material`, `amount` FROM `player_materials` WHERE `player_id` = %d",
		player:getGuid()
	))

	if not query then
		return wallet
	end

	repeat
		local material = Result.getString(query, "material")
		if wallet[material] ~= nil then
			wallet[material] = Result.getNumber(query, "amount")
		end
	until not Result.next(query)

	Result.free(query)
	return wallet
end

function Farming.sendWallet(player)
	local wallet = Farming.getWallet(player)
	player:sendExtendedOpcode(
		Farming.OPCODE,
		string.format("wallet|wood|%d|stone|%d", wallet.wood, wallet.stone)
	)
	return wallet
end

function Farming.sendBuildCatalog(player)
	for material, structures in pairs(Farming.buildCatalog) do
		local parts = { "catalog", material }
		for _, structureType in ipairs({ "wall", "door", "window" }) do
			local config = structures[structureType]
			if config then
				parts[#parts + 1] = structureType
				parts[#parts + 1] = tostring(config.itemId)
				parts[#parts + 1] = tostring(config.cost)
			end
		end
		player:sendExtendedOpcode(Farming.OPCODE, table.concat(parts, "|"))
	end
end

function Farming.addMaterial(player, material, amount)
	if material ~= "wood" and material ~= "stone" then
		return false
	end

	amount = math.max(0, math.floor(tonumber(amount) or 0))
	if amount == 0 then
		return false
	end

	local ok = db.query(string.format(
		"INSERT INTO `player_materials` (`player_id`, `material`, `amount`) VALUES (%d, '%s', %d) " ..
		"ON DUPLICATE KEY UPDATE `amount` = `amount` + VALUES(`amount`)",
		player:getGuid(),
		material,
		amount
	))

	if not ok then
		return false
	end

	local wallet = Farming.sendWallet(player)
	player:sendExtendedOpcode(
		Farming.OPCODE,
		string.format("reward|%s|%d", material, wallet[material] or 0)
	)
	return true
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

function Farming.arm(player)
	local playerId = player:getId()
	Farming.armed[playerId] = os.time() + Farming.ARM_TIMEOUT_SECONDS
	player:sendExtendedOpcode(Farming.OPCODE, "status|armed")
end

function Farming.disarm(player)
	Farming.armed[player:getId()] = nil
end

function Farming.stop(player, reason)
	local playerId = player:getId()
	Farming.sessions[playerId] = nil
	if reason then
		player:sendExtendedOpcode(Farming.OPCODE, "status|stopped|" .. tostring(reason))
	end
end

local function farmingTick(playerId, token)
	local session = Farming.sessions[playerId]
	if not session or session.token ~= token then
		return
	end

	local player = Player(playerId)
	if not player then
		Farming.sessions[playerId] = nil
		return
	end

	if player:getItemCount(Farming.PICK_ITEM_ID) < 1 then
		Farming.stop(player, "pick-missing")
		return
	end

	local position = Position(session.position.x, session.position.y, session.position.z)
	if not isAdjacent(player, position) then
		Farming.stop(player, "too-far")
		player:sendCancelMessage("Move next to the resource to continue farming.")
		return
	end

	local tile = Tile(position)
	local target = tile and tile:getItemById(session.itemId) or nil
	if not target then
		Farming.stop(player, "resource-missing")
		return
	end

	local state = getResourceState(session.resourceKey)
	if state.remainingHits <= 0 then
		Farming.stop(player, "depleted")
		return
	end

	position:sendMagicEffect(CONST_ME_POFF)
	state.remainingHits = state.remainingHits - 1
	session.hitsUntilReward = session.hitsUntilReward - 1

	if session.hitsUntilReward <= 0 then
		Farming.addMaterial(player, session.material, 1)
		session.hitsUntilReward = math.random(Farming.REWARD_HITS_MIN, Farming.REWARD_HITS_MAX)
	end

	if state.remainingHits <= 0 then
		state.remainingHits = 0
		target:remove()

		Farming.stop(player, "depleted")
		player:sendTextMessage(
			MESSAGE_EVENT_ADVANCE,
			"The resource is depleted until the next server save."
		)
		return
	end

	addEvent(farmingTick, Farming.HIT_INTERVAL_MS, playerId, token)
end

function Farming.handlePickUse(player, item, target, toPosition)
	local playerId = player:getId()
	local armedUntil = Farming.armed[playerId]
	if not armedUntil then
		return false, false
	end

	Farming.armed[playerId] = nil
	if armedUntil < os.time() then
		return false, false
	end

	if not target or not target:isItem() then
		player:sendCancelMessage("Select a tree, bush or rock to farm.")
		return true, true
	end

	if not isAdjacent(player, toPosition) then
		player:sendCancelMessage("You need to stand next to the resource.")
		return true, true
	end

	local material = Farming.classifyItem(target)
	if not material then
		local itemType = ItemType(target:getId())
		local itemName = itemType and itemType:getName() or "unknown object"
		player:sendCancelMessage(string.format(
			"%s is not farmable yet (item id %d).",
			itemName ~= "" and itemName or "This object",
			target:getId()
		))
		return true, true
	end

	local resourceKey = positionKey(toPosition, target:getId())
	local state = getResourceState(resourceKey)
	if state.remainingHits <= 0 then
		player:sendCancelMessage("This resource is depleted until the next server save.")
		return true, true
	end

	Farming.sessionSequence = Farming.sessionSequence + 1
	local token = Farming.sessionSequence
	Farming.sessions[playerId] = {
		token = token,
		itemId = target:getId(),
		material = material,
		resourceKey = resourceKey,
		position = {
			x = toPosition.x,
			y = toPosition.y,
			z = toPosition.z,
		},
		hitsUntilReward = math.random(Farming.REWARD_HITS_MIN, Farming.REWARD_HITS_MAX),
	}

	player:sendExtendedOpcode(Farming.OPCODE, "status|started|" .. material)
	player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "Farming started. Stay next to the resource.")
	addEvent(farmingTick, Farming.HIT_INTERVAL_MS, playerId, token)
	return true, true
end

local function parseBuildPositions(raw)
	local positions = {}
	local seen = {}
	for token in tostring(raw or ""):gmatch("[^;]+") do
		local x, y, z = token:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
		if not x then
			return nil, "Invalid build position."
		end

		local position = Position(tonumber(x), tonumber(y), tonumber(z))
		local key = buildPositionKey(position)
		if not seen[key] then
			seen[key] = true
			positions[#positions + 1] = position
			if #positions > Farming.BUILD_MAX_TILES then
				return nil, string.format("You can queue at most %d tiles at once.", Farming.BUILD_MAX_TILES)
			end
		end
	end

	if #positions == 0 then
		return nil, "Select at least one tile to build."
	end

	return positions
end

local function validateBuildTile(player, position)
	if not isWithinBuildRange(player, position) then
		return false, "All construction tiles must be within 7 squares of your character."
	end

	local key = buildPositionKey(position)
	if Farming.structurePositions[key] then
		return false, "There is already a player structure on one of the selected tiles."
	end

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

local function cleanupBuiltItems(items)
	for _, item in ipairs(items) do
		if item then
			item:remove()
		end
	end
end

function Farming.confirmBuild(player, material, structureType, rawPositions)
	local materialCatalog = Farming.buildCatalog[material]
	local config = materialCatalog and materialCatalog[structureType] or nil
	if not config then
		buildError(player, "Unknown construction type.")
		return true
	end

	local positions, parseError = parseBuildPositions(rawPositions)
	if not positions then
		buildError(player, parseError)
		return true
	end

	for _, position in ipairs(positions) do
		local valid, reason = validateBuildTile(player, position)
		if not valid then
			buildError(player, reason)
			return true
		end
	end

	local totalCost = config.cost * #positions
	local wallet = Farming.getWallet(player)
	if (wallet[material] or 0) < totalCost then
		buildError(player, string.format("You need %d %s for this construction.", totalCost, material))
		return true
	end

	-- Create runtime objects first. They are removed again if persistence fails.
	local createdItems = {}
	for _, position in ipairs(positions) do
		local created = Game.createItem(config.itemId, 1, position)
		if not created then
			cleanupBuiltItems(createdItems)
			buildError(player, "The server could not create one of the structures.")
			return true
		end
		createdItems[#createdItems + 1] = created
	end

	local values = {}
	for _, position in ipairs(positions) do
		values[#values + 1] = string.format(
			"(%d, '%s', '%s', %d, %d, %d, %d)",
			player:getGuid(), material, structureType, config.itemId, position.x, position.y, position.z
		)
	end

	local insertOk = db.query(
		"INSERT INTO `player_structures` (`player_id`, `material`, `structure_type`, `item_id`, `pos_x`, `pos_y`, `pos_z`) VALUES " .. table.concat(values, ",")
	)
	if not insertOk then
		cleanupBuiltItems(createdItems)
		buildError(player, "Those tiles could not be reserved for construction.")
		return true
	end

	if not spendMaterial(player, material, totalCost) then
		cleanupBuiltItems(createdItems)
		local conditions = {}
		for _, position in ipairs(positions) do
			conditions[#conditions + 1] = string.format("(`pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d)", position.x, position.y, position.z)
		end
		db.query("DELETE FROM `player_structures` WHERE `player_id`=" .. player:getGuid() .. " AND (" .. table.concat(conditions, " OR ") .. ")")
		buildError(player, "Your material balance changed before construction was confirmed.")
		return true
	end

	for _, position in ipairs(positions) do
		Farming.structurePositions[buildPositionKey(position)] = true
	end

	local newWallet = Farming.getWallet(player)
	player:sendExtendedOpcode(
		Farming.OPCODE,
		string.format("build|success|%s|%s|%d|%d|%d", material, structureType, #positions, totalCost, newWallet[material] or 0)
	)
	player:sendTextMessage(
		MESSAGE_EVENT_ADVANCE,
		string.format("Built %d %s structure%s for %d %s.", #positions, structureType, #positions == 1 and "" or "s", totalCost, material)
	)
	return true
end

function Farming.restoreStructures()
	Farming.structurePositions = {}
	local query = db.storeQuery("SELECT `id`, `item_id`, `pos_x`, `pos_y`, `pos_z` FROM `player_structures` ORDER BY `id`")
	if not query then
		logger.info("[Farming] No persistent player structures to restore.")
		return true
	end

	local restoredCount = 0
	repeat
		local id = Result.getNumber(query, "id")
		local itemId = Result.getNumber(query, "item_id")
		local position = Position(
			Result.getNumber(query, "pos_x"),
			Result.getNumber(query, "pos_y"),
			Result.getNumber(query, "pos_z")
		)
		local key = buildPositionKey(position)
		local tile = Tile(position)

		if tile and tile:getItemById(itemId) then
			Farming.structurePositions[key] = true
			restoredCount = restoredCount + 1
		elseif tile and not tile:hasFlag(TILESTATE_BLOCKSOLID) then
			local item = Game.createItem(itemId, 1, position)
			if item then
				Farming.structurePositions[key] = true
				restoredCount = restoredCount + 1
			else
				logger.warn("[Farming] Could not restore player structure {} at {}:{}:{}", id, position.x, position.y, position.z)
			end
		else
			logger.warn("[Farming] Skipped player structure {} because its base tile is blocked or missing at {}:{}:{}", id, position.x, position.y, position.z)
		end
	until not Result.next(query)

	Result.free(query)
	logger.info("[Farming] Restored {} persistent player structures.", restoredCount)
	return true
end

function Farming.handleOpcode(player, buffer)
	buffer = tostring(buffer or "")
	if buffer == "arm" then
		Farming.arm(player)
		return true
	elseif buffer == "sync" then
		Farming.sendWallet(player)
		Farming.sendBuildCatalog(player)
		return true
	elseif buffer == "stop" then
		Farming.disarm(player)
		Farming.stop(player, "client-stop")
		return true
	end

	local material, structureType, positions = buffer:match("^build|confirm|([^|]+)|([^|]+)|(.+)$")
	if material and structureType and positions then
		Farming.disarm(player)
		Farming.stop(player)
		return Farming.confirmBuild(player, material, structureType, positions)
	end

	return false
end
