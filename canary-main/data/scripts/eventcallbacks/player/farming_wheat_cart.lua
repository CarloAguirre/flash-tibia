local wheatCartExchange = EventCallback("FarmingWheatCartExchange")

local WHEAT_ID = 3605
local CART_POSITIONS = {
	["32377:32208:7"] = true,
	["32377:32209:7"] = true,
	["32377:32210:7"] = true,
}

local function positionKey(position)
	if not position or position.x == CONTAINER_POSITION then
		return nil
	end

	return string.format("%d:%d:%d", position.x, position.y, position.z)
end

local function isCartPosition(position)
	local key = positionKey(position)
	return key and CART_POSITIONS[key] == true
end

local function isProtectedCartDecoration(item, fromPosition)
	return item
		and isCartPosition(fromPosition)
		and item:getActionId() == IMMOVABLE_ACTION_ID
end

function wheatCartExchange.playerOnMoveItem(player, item, count, fromPosition, toPosition, fromCylinder, toCylinder)
	if not item then
		return true
	end

	-- The three wheelbarrow pieces and the wheat displayed on its rear square are
	-- scenery. Block their movement explicitly as well as marking them immovable,
	-- so even privileged/admin characters cannot pick the decorative wheat up.
	if isProtectedCartDecoration(item, fromPosition) then
		if item:getId() == WHEAT_ID then
			player:sendCancelMessage("That wheat is part of the cart display.")
		else
			player:sendCancelMessage("You cannot move the wheat cart.")
		end
		return false
	end

	if not isCartPosition(toPosition) then
		return true
	end

	-- Player-owned harvested wheat can be dropped on any of the three cart squares,
	-- including directly on top of the decorative wheat on the rear square.
	if item:getId() ~= WHEAT_ID then
		player:sendCancelMessage("The wheat cart only accepts harvested wheat.")
		return false
	end

	local stackCount = item:getCount()
	local amount = math.min(math.max(tonumber(count) or 1, 1), stackCount)

	-- Add the payment first. If the player has no room/capacity, leave the wheat
	-- untouched and cancel the move. Returning false prevents the original drop.
	local reward = player:addItem(ITEM_GOLD_COIN, amount)
	if not reward then
		player:sendCancelMessage("You do not have enough room for the gold coins.")
		return false
	end

	-- The callback runs before the physical move. Consume the source stack here;
	-- if that unexpectedly fails, roll the payment back to keep the exchange atomic.
	if not item:remove(amount) then
		player:removeItem(ITEM_GOLD_COIN, amount)
		player:sendCancelMessage("The wheat could not be sold.")
		return false
	end

	local suffix = amount == 1 and "" or "s"
	player:sendTextMessage(
		MESSAGE_EVENT_ADVANCE,
		string.format("You sold %d wheat for %d gold coin%s.", amount, amount, suffix)
	)

	return false
end

wheatCartExchange:register()
