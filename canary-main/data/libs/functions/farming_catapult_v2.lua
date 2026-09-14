-- Catapult placement v2.
-- Keeps the existing siege combat/runtime, but allows the 2x2 footprint to be
-- positioned up to two squares from the operator while requiring every part to
-- sit on the player's own generated upper platform.

if not Farming then
	return
end

local CATAPULT_COST = 30
local CATAPULT_BUILD_MS = 2000
local CATAPULT_PARTS = {
	{ structureType = "catapult_nw", itemId = 5609, dx = 0, dy = 0 },
	{ structureType = "catapult_ne", itemId = 5610, dx = 1, dy = 0 },
	{ structureType = "catapult_sw", itemId = 5611, dx = 0, dy = 1 },
	{ structureType = "catapult_se", itemId = 5612, dx = 1, dy = 1 },
}

local function positionKey(position)
	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local function catapultPartPosition(anchor, part)
	return Position(anchor.x + part.dx, anchor.y + part.dy, anchor.z)
end

local function chebyshevDistance(a, b)
	if a.z ~= b.z then
		return math.huge
	end
	return math.max(math.abs(a.x - b.x), math.abs(a.y - b.y))
end

local function ownsPlatformAt(playerGuid, position)
	local query = db.storeQuery(string.format(
		"SELECT `id` FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='platform' " ..
		"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d LIMIT 1",
		playerGuid, position.x, position.y, position.z
	))
	if not query then
		return false
	end
	Result.free(query)
	return true
end

local function parseAnchor(rawPayload)
	local raw = tostring(rawPayload or "")
	local v2 = raw:match("^v2|(.+)$") or raw
	local first = v2:match("^[^;]+")
	if not first then
		return nil
	end
	local x, y, z = first:match("^(%-?%d+),(%-?%d+),(%-?%d+),?[01]?$" )
	if not x then
		x, y, z = first:match("^(%-?%d+),(%-?%d+),(%-?%d+)$")
	end
	if not x then
		return nil
	end
	return Position(tonumber(x), tonumber(y), tonumber(z))
end

local function validateAnchor(player, anchor, ignoreReservations)
	if not anchor then
		return false, "Invalid catapult position."
	end

	local playerPosition = player:getPosition()
	local playerGuid = player:getGuid()
	if not ownsPlatformAt(playerGuid, playerPosition) then
		return false, "You must stand on your supported upper platform to build a catapult."
	end
	if chebyshevDistance(playerPosition, anchor) > 2 then
		return false, "Place the catapult within two squares of your character."
	end

	for _, part in ipairs(CATAPULT_PARTS) do
		local position = catapultPartPosition(anchor, part)
		if not ownsPlatformAt(playerGuid, position) then
			return false, "A catapult needs a complete 2x2 area of your supported upper floor."
		end
		if not ignoreReservations and Farming.structurePositions[positionKey(position)] then
			return false, "One of the catapult squares is already occupied."
		end
		local tile = Tile(position)
		if not tile or not tile:getGround() then
			return false, "One of the catapult squares has no floor."
		end
		if tile:hasFlag(TILESTATE_BLOCKSOLID) or tile:getCreatureCount() > 0 then
			return false, "One of the catapult squares is blocked."
		end
	end
	return true
end

local function deleteRows(playerGuid, anchor)
	for _, part in ipairs(CATAPULT_PARTS) do
		local position = catapultPartPosition(anchor, part)
		db.query(string.format(
			"DELETE FROM `player_structures` WHERE `player_id`=%d AND `structure_type`='%s' " ..
			"AND `pos_x`=%d AND `pos_y`=%d AND `pos_z`=%d",
			playerGuid, part.structureType, position.x, position.y, position.z
		))
		Farming.structurePositions[positionKey(position)] = nil
	end
end

local function refund(playerGuid)
	db.query(string.format(
		"INSERT INTO `player_materials` (`player_id`,`material`,`amount`) VALUES (%d,'wood',%d) " ..
		"ON DUPLICATE KEY UPDATE `amount`=`amount`+VALUES(`amount`)",
		playerGuid, CATAPULT_COST
	))
end

local function dust(anchor)
	for _, part in ipairs(CATAPULT_PARTS) do
		catapultPartPosition(anchor, part):sendMagicEffect(CONST_ME_POFF)
	end
end

local function completeBuild(playerId, playerGuid, anchorData)
	local anchor = Position(anchorData.x, anchorData.y, anchorData.z)
	local player = Player(playerId)
	if player and player:getGuid() ~= playerGuid then
		player = nil
	end

	local valid = true
	for _, part in ipairs(CATAPULT_PARTS) do
		local position = catapultPartPosition(anchor, part)
		if not ownsPlatformAt(playerGuid, position) then
			valid = false
			break
		end
		local tile = Tile(position)
		if not tile or tile:hasFlag(TILESTATE_BLOCKSOLID) or tile:getCreatureCount() > 0 then
			valid = false
			break
		end
	end

	local created = {}
	if valid then
		for _, part in ipairs(CATAPULT_PARTS) do
			local position = catapultPartPosition(anchor, part)
			local item = Game.createItem(part.itemId, 1, position)
			if not item then
				valid = false
				break
			end
			created[#created + 1] = item
		end
	end

	if not valid then
		for _, item in ipairs(created) do
			item:remove()
		end
		deleteRows(playerGuid, anchor)
		refund(playerGuid)
		if player then
			Farming.sendWallet(player)
			player:sendExtendedOpcode(Farming.OPCODE, "build|error|The catapult area became unavailable; your wood was refunded.")
			player:sendCancelMessage("The catapult area became unavailable; your wood was refunded.")
		end
		return
	end

	for _, part in ipairs(CATAPULT_PARTS) do
		catapultPartPosition(anchor, part):sendMagicEffect(CONST_ME_BLOCKHIT)
	end
	if player then
		local wallet = Farming.sendWallet(player)
		player:sendExtendedOpcode(Farming.OPCODE, string.format("build|success|wood|catapult|1|%d|%d|0", CATAPULT_COST, wallet.wood or 0))
		player:sendTextMessage(MESSAGE_EVENT_ADVANCE, string.format("Built a catapult for %d wood.", CATAPULT_COST))
		if Farming.sendSiegeStatus then
			Farming.sendSiegeStatus(player)
		end
	end
end

local function confirmCatapultV2(player, rawPayload)
	local anchor = parseAnchor(rawPayload)
	local valid, reason = validateAnchor(player, anchor, false)
	if not valid then
		player:sendExtendedOpcode(Farming.OPCODE, "build|error|" .. reason)
		player:sendCancelMessage(reason)
		return true
	end

	local wallet = Farming.getWallet(player)
	if (wallet.wood or 0) < CATAPULT_COST then
		local message = string.format("You need %d wood for a catapult.", CATAPULT_COST)
		player:sendExtendedOpcode(Farming.OPCODE, "build|error|" .. message)
		player:sendCancelMessage(message)
		return true
	end

	local values = {}
	for _, part in ipairs(CATAPULT_PARTS) do
		local position = catapultPartPosition(anchor, part)
		values[#values + 1] = string.format(
			"(%d,'wood','%s',%d,%d,%d,%d)",
			player:getGuid(), part.structureType, part.itemId, position.x, position.y, position.z
		)
	end
	if not db.query(
		"INSERT INTO `player_structures` (`player_id`,`material`,`structure_type`,`item_id`,`pos_x`,`pos_y`,`pos_z`) VALUES " ..
		table.concat(values, ",")
	) then
		player:sendExtendedOpcode(Farming.OPCODE, "build|error|Could not reserve the catapult area.")
		return true
	end

	if not db.query(string.format(
		"UPDATE `player_materials` SET `amount`=`amount`-%d WHERE `player_id`=%d AND `material`='wood' AND `amount`>=%d",
		CATAPULT_COST, player:getGuid(), CATAPULT_COST
	)) then
		deleteRows(player:getGuid(), anchor)
		player:sendExtendedOpcode(Farming.OPCODE, "build|error|Could not spend the required wood.")
		return true
	end

	for _, part in ipairs(CATAPULT_PARTS) do
		Farming.structurePositions[positionKey(catapultPartPosition(anchor, part))] = true
	end
	Farming.sendWallet(player)
	dust(anchor)
	local anchorData = { x = anchor.x, y = anchor.y, z = anchor.z }
	addEvent(dust, 900, anchorData)
	addEvent(completeBuild, CATAPULT_BUILD_MS, player:getId(), player:getGuid(), anchorData)
	return true
end

local previousConfirmBuild = Farming.confirmBuild
function Farming.confirmBuild(player, material, structureType, rawPayload)
	if material == "wood" and structureType == "catapult" then
		return confirmCatapultV2(player, rawPayload)
	end
	return previousConfirmBuild(player, material, structureType, rawPayload)
end
