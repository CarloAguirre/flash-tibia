local playerStructuresStartup = GlobalEvent("PlayerStructuresStartup")

function playerStructuresStartup.onStartup()
	-- The OTBM is already loaded when startup GlobalEvents execute. Reapply the
	-- persistent construction layer after the immutable base world is ready.
	addEvent(function()
		if Farming and Farming.restoreStructures then
			Farming.restoreStructures()
		end
	end, 1000)
	return true
end

playerStructuresStartup:register()
