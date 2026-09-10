local thaisFarmingPlot = GlobalEvent("ThaisFarmingPlotStartup")

local PLOT = {
	from = Position(32372, 32205, 7),
	to = Position(32383, 32212, 7),
	expectedGroundId = 4515,
	farmlandGroundId = 950,
}

local function applyPlotGround()
	local changed = 0
	local skipped = 0

	for x = PLOT.from.x, PLOT.to.x do
		for y = PLOT.from.y, PLOT.to.y do
			local position = Position(x, y, PLOT.from.z)
			local tile = Tile(position)
			if not tile then
				skipped = skipped + 1
			else
				local ground = tile:getGround()
				if not ground then
					skipped = skipped + 1
				elseif ground:getId() == PLOT.farmlandGroundId then
					-- Already applied (useful for script reloads during development).
				elseif ground:getId() == PLOT.expectedGroundId then
					-- Transform only the ground. Decorative/top items already present in
					-- the OTBM are intentionally preserved.
					ground:transform(PLOT.farmlandGroundId)
					changed = changed + 1
				else
					-- Conservative safety guard: if this part of Thais changes in the
					-- base map, do not overwrite an unexpected ground automatically.
					skipped = skipped + 1
				end
			end
		end
	end

	logger.info(
		"[ThaisFarmingPlotStartup] Applied farmland ground {} to {} tiles ({} skipped) in {}..{}",
		PLOT.farmlandGroundId,
		changed,
		skipped,
		PLOT.from,
		PLOT.to
	)
end

function thaisFarmingPlot.onStartup()
	-- Startup GlobalEvents run after the OTBM is loaded, so this becomes a
	-- small code-controlled world overlay without modifying otservbr.otbm.
	applyPlotGround()
	return true
end

thaisFarmingPlot:register()
