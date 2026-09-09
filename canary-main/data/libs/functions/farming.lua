Farming = Farming or {}

Farming.OPCODE = 217
Farming.PICK_ITEM_ID = 3456
Farming.ARM_TIMEOUT_SECONDS = 10
Farming.HIT_INTERVAL_MS = 1000
Farming.REWARD_HITS_MIN = 1
Farming.REWARD_HITS_MAX = 3
Farming.RESOURCE_HITS_MIN = 8
Farming.RESOURCE_HITS_MAX = 12
Farming.RESOURCE_RESPAWN_SECONDS = 30

Farming.armed = Farming.armed or {}
Farming.sessions = Farming.sessions or {}
Farming.resourceStates = Farming.resourceStates or {}
Farming.sessionSequence = Farming.sessionSequence or 0

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

local function isAdjacent(player, position)
	local playerPosition = player:getPosition()
	if playerPosition.z ~= position.z then
		return false
	end

	return math.max(math.abs(playerPosition.x - position.x), math.abs(playerPosition.y - position.y)) <= 1
end

local function getResourceState(key)
	local state = Farming.resourceStates[key]
	local now = os.time()

	if not state then
		state = {
			remainingHits = math.random(Farming.RESOURCE_HITS_MIN, Farming.RESOURCE_HITS_MAX),
			depletedUntil = 0,
		}
		Farming.resourceStates[key] = state
	elseif state.depletedUntil > 0 and state.depletedUntil <= now then
		state.remainingHits = math.random(Farming.RESOURCE_HITS_MIN, Farming.RESOURCE_HITS_MAX)
		state.depletedUntil = 0
	end

	return state
end

local function respawnResource(resourceKey, itemId, x, y, z)
	local position = Position(x, y, z)
	local tile = Tile(position)

	-- A restart reloads the original OTBM, so the resource may already exist
	-- when this delayed event is reached in unusual reload scenarios.
	if tile and tile:getItemById(itemId) then
		local existingState = Farming.resourceStates[resourceKey]
		if existingState then
			existingState.remainingHits = math.random(Farming.RESOURCE_HITS_MIN, Farming.RESOURCE_HITS_MAX)
			existingState.depletedUntil = 0
		end
		return
	end

	local restored = Game.createItem(itemId, 1, position)
	if not restored then
		return
	end

	local state = Farming.resourceStates[resourceKey]
	if not state then
		state = {}
		Farming.resourceStates[resourceKey] = state
	end
	state.remainingHits = math.random(Farming.RESOURCE_HITS_MIN, Farming.RESOURCE_HITS_MAX)
	state.depletedUntil = 0

	position:sendMagicEffect(CONST_ME_POFF)
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
	if state.depletedUntil > os.time() then
		Farming.stop(player, "depleted")
		player:sendCancelMessage("This resource is depleted. Try again shortly.")
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
		state.depletedUntil = os.time() + Farming.RESOURCE_RESPAWN_SECONDS

		local removed = target:remove()
		if removed then
			addEvent(
				respawnResource,
				Farming.RESOURCE_RESPAWN_SECONDS * 1000,
				session.resourceKey,
				session.itemId,
				session.position.x,
				session.position.y,
				session.position.z
			)
		end

		Farming.stop(player, "depleted")
		player:sendTextMessage(
			MESSAGE_EVENT_ADVANCE,
			string.format("The resource was depleted and will regrow in %d seconds.", Farming.RESOURCE_RESPAWN_SECONDS)
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
	if state.depletedUntil > os.time() then
		player:sendCancelMessage("This resource is depleted. Try again shortly.")
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

function Farming.handleOpcode(player, buffer)
	buffer = tostring(buffer or "")
	if buffer == "arm" then
		Farming.arm(player)
		return true
	elseif buffer == "sync" then
		Farming.sendWallet(player)
		return true
	elseif buffer == "stop" then
		Farming.disarm(player)
		Farming.stop(player, "client-stop")
		return true
	end

	return false
end
