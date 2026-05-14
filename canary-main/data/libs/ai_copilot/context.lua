local context = {}

local function getPercent(currentValue, maxValue)
	currentValue = tonumber(currentValue) or 0
	maxValue = tonumber(maxValue) or 0
	if maxValue <= 0 then
		return 0
	end
	return math.floor((currentValue * 100) / maxValue)
end

function context.build(player)
	local position = player:getPosition()
	local vocation = player:getVocation()
	local vocationName = vocation and vocation:getName() or "Unknown"

	return {
		player = {
			name = player:getName(),
			level = player:getLevel(),
			vocation = vocationName,
			position = {
				x = position.x,
				y = position.y,
				z = position.z,
			},
			healthPercent = getPercent(player:getHealth(), player:getMaxHealth()),
			manaPercent = getPercent(player:getMana(), player:getMaxMana()),
		},
		server = {
			name = SERVER_NAME or "Eldera",
			rates = {
				exp = SCHEDULE_EXP_RATE or 100,
				loot = SCHEDULE_LOOT_RATE or 100,
				skill = SCHEDULE_SKILL_RATE or 100,
				spawn = SCHEDULE_SPAWN_RATE or 100,
			},
		},
		permissions = {
			canSuggestRoute = false,
			canSuggestTask = false,
			canExecuteAction = false,
		},
	}
end

return context