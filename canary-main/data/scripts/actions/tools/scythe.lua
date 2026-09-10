local scythe = Action()

local WHEAT = {
	cut = 3651,
	growing = 3652,
	ripe = 3653,
	reward = 3605, -- bunch of wheat
	stageDurationMs = 2000,
}

-- One successful harvest grants exactly one thousandth (0.1%) of the
-- requirement for the player's current character level and magic level.
-- Fractional points are kept in the player's persistent KV store so low-level
-- requirements that are not divisible by 1000 still remain exact over time.
local WHEAT_PROGRESS = {
	divisor = 1000,
	levelRemainderKey = "farming.wheat.level-progress-remainder",
	levelTrackerKey = "farming.wheat.level-progress-level",
	magicRemainderKey = "farming.wheat.magic-progress-remainder",
	magicTrackerKey = "farming.wheat.magic-progress-level",
}

-- Keep the per-harvest feedback compact because the player can harvest many
-- tiles in quick succession. Both the visual effect and speech are sent only
-- to the harvesting player, so nearby players are not spammed.
local WHEAT_PROGRESS_FEEDBACK = {
	text = "+0.1% LVL | +0.1% ML",
	effect = CONST_ME_MAGIC_BLUE,
}

local function getKvNumber(kv, key, defaultValue)
	local value = kv:get(key)
	if type(value) ~= "number" then
		return defaultValue
	end
	return value
end

local function getOneThousandth(requirement, remainder)
	local numerator = requirement + remainder
	return math.floor(numerator / WHEAT_PROGRESS.divisor), numerator % WHEAT_PROGRESS.divisor
end

local function addWheatLevelProgress(player)
	local level = player:getLevel()
	local currentLevelExperience = Game.getExperienceForLevel(level)
	local nextLevelExperience = Game.getExperienceForLevel(level + 1)
	local requirement = nextLevelExperience - currentLevelExperience
	if not requirement or requirement <= 0 then
		return
	end

	local kv = player:kv()
	local trackedLevel = getKvNumber(kv, WHEAT_PROGRESS.levelTrackerKey, level)
	local remainder = 0
	if trackedLevel == level then
		remainder = getKvNumber(kv, WHEAT_PROGRESS.levelRemainderKey, 0)
	end

	local amount, newRemainder = getOneThousandth(requirement, remainder)
	if amount > 0 then
		-- No per-harvest experience message: the native progress bar simply moves.
		player:addExperience(amount, false)
	end

	local newLevel = player:getLevel()
	if newLevel ~= level then
		kv:set(WHEAT_PROGRESS.levelTrackerKey, newLevel)
		kv:set(WHEAT_PROGRESS.levelRemainderKey, 0)
	else
		kv:set(WHEAT_PROGRESS.levelTrackerKey, level)
		kv:set(WHEAT_PROGRESS.levelRemainderKey, newRemainder)
	end
end

local function addWheatMagicProgress(player)
	local vocation = player:getVocation()
	if not vocation then
		return
	end

	local magicLevel = player:getBaseMagicLevel()
	local requirement = vocation:getRequiredManaSpent(magicLevel + 1)
	if not requirement or requirement <= 0 then
		return
	end

	local kv = player:kv()
	local trackedMagicLevel = getKvNumber(kv, WHEAT_PROGRESS.magicTrackerKey, magicLevel)
	local remainder = 0
	if trackedMagicLevel == magicLevel then
		remainder = getKvNumber(kv, WHEAT_PROGRESS.magicRemainderKey, 0)
	end

	local amount, newRemainder = getOneThousandth(requirement, remainder)
	if amount > 0 then
		-- The second argument bypasses Canary's configured skill-rate multiplier,
		-- keeping the farming reward at a real 0.1% regardless of server rates.
		player:addManaSpent(amount, true)
	end

	local newMagicLevel = player:getBaseMagicLevel()
	if newMagicLevel ~= magicLevel then
		kv:set(WHEAT_PROGRESS.magicTrackerKey, newMagicLevel)
		kv:set(WHEAT_PROGRESS.magicRemainderKey, 0)
	else
		kv:set(WHEAT_PROGRESS.magicTrackerKey, magicLevel)
		kv:set(WHEAT_PROGRESS.magicRemainderKey, newRemainder)
	end
end

local function addWheatProgress(player)
	addWheatLevelProgress(player)
	addWheatMagicProgress(player)
end

local function showWheatProgressFeedback(player)
	local position = player:getPosition()
	position:sendMagicEffect(WHEAT_PROGRESS_FEEDBACK.effect, player)
	player:say(WHEAT_PROGRESS_FEEDBACK.text, TALKTYPE_MONSTER_SAY, false, player, position)
end

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

	-- Progress and its feedback are granted only after a real, successful harvest.
	addWheatProgress(player)
	showWheatProgressFeedback(player)
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
