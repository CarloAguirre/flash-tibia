local scythe = Action()

local WHEAT = {
	cut = 3651,
	growing = 3652,
	ripe = 3653,
	reward = 3605, -- bunch of wheat
	stageDurationMs = 2000,
}

local function transformWheatAt(x, y, z, expectedId, nextId)
	local tile = Tile(Position(x, y, z))
	if not tile then
		return
	end

	local wheat = tile:getItemById(expectedId)
	if wheat then
		wheat:transform(nextId)
	end
end

local function scheduleWheatRegrowth(position)
	-- Keep the existing Tibia wheat states, but make the cycle explicit and fast:
	-- cut wheat (3651) for 2 s -> growing wheat (3652) for 2 s -> ripe wheat (3653).
	addEvent(
		transformWheatAt,
		WHEAT.stageDurationMs,
		position.x,
		position.y,
		position.z,
		WHEAT.cut,
		WHEAT.growing
	)
	addEvent(
		transformWheatAt,
		WHEAT.stageDurationMs * 2,
		position.x,
		position.y,
		position.z,
		WHEAT.growing,
		WHEAT.ripe
	)
end

local function harvestWheat(player, target)
	local backpack = player:getSlotItem(CONST_SLOT_BACKPACK)
	if not backpack then
		player:sendCancelMessage("You need a backpack to harvest wheat.")
		return true
	end

	-- Add the harvest directly to the equipped backpack. Unlike the original
	-- behavior, nothing is created on the ground.
	local harvested = backpack:addItem(WHEAT.reward, 1)
	if not harvested then
		player:sendCancelMessage("There is not enough room in your backpack.")
		return true
	end

	local position = target:getPosition()
	target:transform(WHEAT.cut)
	scheduleWheatRegrowth(position)
	return true
end

function scythe.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	-- Preserve Canary's normal scythe behavior for every other target, but use
	-- our farming loop for ripe wheat.
	if target and target.itemid == WHEAT.ripe then
		return harvestWheat(player, target)
	end

	return onUseScythe(player, item, fromPosition, target, toPosition, isHotkey)
end

scythe:id(3453)
scythe:register()
