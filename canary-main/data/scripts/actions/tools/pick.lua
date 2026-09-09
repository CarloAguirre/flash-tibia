local pick = Action()

function pick.onUse(player, item, fromPosition, target, toPosition, isHotkey)
	if Farming then
		local handled, result = Farming.handlePickUse(player, item, target, toPosition)
		if handled then
			return result
		end
	end

	return onUsePick(player, item, fromPosition, target, toPosition, isHotkey)
end

pick:id(3456)
pick:register()
