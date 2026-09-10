local thaisFarmingPlot = GlobalEvent("ThaisFarmingPlotStartup")

local PLOT = {
	from = Position(32372, 32205, 7),
	to = Position(32383, 32212, 7),
	dirtGroundId = 950,
	cropGroundId = 952,
	wheatGreenId = 3652,
	wheatRipeId = 3653,
	flowerId = 3654,
	flowerDetailId = 2899,
}

local CROP_ROWS = {
	[32206] = true,
	[32208] = true,
	[32210] = true,
}

local function clearTopItems(tile)
	local removed = 0
	local items = tile:getItems()
	if not items then
		return removed
	end

	-- Remove every non-ground item from this deliberately repurposed park area:
	-- trees, bushes, statue/fountain pieces and the previous decorations.
	for i = #items, 1, -1 do
		local item = items[i]
		if item and item:remove() then
			removed = removed + 1
		end
	end

	return removed
end

local function setGround(tile, position, groundId)
	local ground = tile:getGround()
	if ground then
		if ground:getId() ~= groundId then
			ground:transform(groundId)
		end
		return true
	end

	return Game.createItem(groundId, 1, position) ~= nil
end

local function plant(position, itemId)
	return Game.createItem(itemId, 1, position) ~= nil
end

local function addFlowerPatch(position)
	plant(position, PLOT.flowerId)
	plant(position, PLOT.flowerDetailId)
end

local function applyBasePlot()
	local changedGrounds = 0
	local removedItems = 0
	local missingTiles = 0

	for x = PLOT.from.x, PLOT.to.x do
		for y = PLOT.from.y, PLOT.to.y do
			local position = Position(x, y, PLOT.from.z)
			local tile = Tile(position)
			if not tile then
				missingTiles = missingTiles + 1
			else
				removedItems = removedItems + clearTopItems(tile)

				local groundId = CROP_ROWS[y] and PLOT.cropGroundId or PLOT.dirtGroundId
				local ground = tile:getGround()
				if not ground or ground:getId() ~= groundId then
					if setGround(tile, position, groundId) then
						changedGrounds = changedGrounds + 1
					end
				end
			end
		end
	end

	return changedGrounds, removedItems, missingTiles
end

local function plantCropRows()
	local planted = 0
	local z = PLOT.from.z

	-- Northern row: mostly young/green wheat with a few mature plants.
	for x = 32373, 32382 do
		local itemId = (x == 32375 or x == 32379 or x == 32382) and PLOT.wheatRipeId or PLOT.wheatGreenId
		if plant(Position(x, 32206, z), itemId) then
			planted = planted + 1
		end
	end

	-- Central row: intentionally broken in the middle to create a small access gap.
	for x = 32373, 32382 do
		if x ~= 32377 and x ~= 32378 then
			local itemId = (x % 2 == 0) and PLOT.wheatGreenId or PLOT.wheatRipeId
			if plant(Position(x, 32208, z), itemId) then
				planted = planted + 1
			end
		end
	end

	-- Southern row: more mature wheat, with two empty squares so the plot does
	-- not look like a mechanically filled rectangle.
	for x = 32373, 32382 do
		if x ~= 32375 and x ~= 32380 then
			local itemId = (x == 32373 or x == 32378) and PLOT.wheatGreenId or PLOT.wheatRipeId
			if plant(Position(x, 32210, z), itemId) then
				planted = planted + 1
			end
		end
	end

	return planted
end

local function decoratePlot()
	local z = PLOT.from.z

	-- Small flower beds act as visual anchors while keeping the farm open to the
	-- surrounding Thais paths (no fence by design).
	local flowerPositions = {
		Position(32372, 32205, z),
		Position(32383, 32205, z),
		Position(32372, 32212, z),
		Position(32383, 32212, z),
		Position(32372, 32208, z),
		Position(32383, 32208, z),
	}

	for _, position in ipairs(flowerPositions) do
		addFlowerPatch(position)
	end
end

local function applyPlot()
	local changedGrounds, removedItems, missingTiles = applyBasePlot()
	local planted = plantCropRows()
	decoratePlot()

	logger.info(
		"[ThaisFarmingPlotStartup] Urban farm ready: {} grounds changed, {} old decorations removed, {} crops planted, {} missing tiles",
		changedGrounds,
		removedItems,
		planted,
		missingTiles
	)
end

function thaisFarmingPlot.onStartup()
	-- The OTBM remains the immutable base. Every restart rebuilds this small
	-- urban farming overlay after the world has loaded.
	applyPlot()
	return true
end

thaisFarmingPlot:register()
