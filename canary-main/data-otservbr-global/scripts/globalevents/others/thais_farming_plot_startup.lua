local thaisFarmingPlot = GlobalEvent("ThaisFarmingPlotStartup")

local PLOT = {
	from = Position(32372, 32205, 7),
	to = Position(32383, 32212, 7),
	grassGroundId = 106,
	dirtGroundId = 950,
	cropGroundId = 952,
	wheatGreenId = 3652,
	wheatRipeId = 3653,
	flowerId = 3654,
	flowerDetailId = 2899,
	borders = {
		north = { 4658 },
		south = { 4533, 4656 },
		east = { 4532, 4659 },
		west = { 4534, 4657 },
	},
}

local CROP_ROWS = {
	[32206] = true,
	[32208] = true,
	[32210] = true,
}

local function isCorner(x, y)
	return (x == PLOT.from.x or x == PLOT.to.x) and (y == PLOT.from.y or y == PLOT.to.y)
end

local function borderSide(x, y)
	-- Corner sprites are deliberately not guessed yet. We only apply the four
	-- cardinal borders measured from the reference farm.
	if isCorner(x, y) then
		return nil
	end
	if y == PLOT.from.y then
		return "north"
	end
	if y == PLOT.to.y then
		return "south"
	end
	if x == PLOT.from.x then
		return "west"
	end
	if x == PLOT.to.x then
		return "east"
	end
	return nil
end

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

local function createItem(position, itemId)
	return Game.createItem(itemId, 1, position) ~= nil
end

local function addItems(position, itemIds)
	local created = 0
	for _, itemId in ipairs(itemIds) do
		if createItem(position, itemId) then
			created = created + 1
		end
	end
	return created
end

local function addFlowerPatch(position)
	createItem(position, PLOT.flowerId)
	createItem(position, PLOT.flowerDetailId)
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

				local side = borderSide(x, y)
				local groundId
				if side then
					-- The reference farm uses ordinary grass (106) underneath its dirt
					-- transition sprites, rather than a hard rectangle of dirt.
					groundId = PLOT.grassGroundId
				else
					groundId = CROP_ROWS[y] and PLOT.cropGroundId or PLOT.dirtGroundId
				end

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

local function applyMeasuredBorders()
	local created = 0
	local z = PLOT.from.z

	-- North/south edges, excluding corners until their exact sprites are sampled.
	for x = PLOT.from.x + 1, PLOT.to.x - 1 do
		created = created + addItems(Position(x, PLOT.from.y, z), PLOT.borders.north)
		created = created + addItems(Position(x, PLOT.to.y, z), PLOT.borders.south)
	end

	-- West/east edges, excluding corners for the same reason.
	for y = PLOT.from.y + 1, PLOT.to.y - 1 do
		created = created + addItems(Position(PLOT.from.x, y, z), PLOT.borders.west)
		created = created + addItems(Position(PLOT.to.x, y, z), PLOT.borders.east)
	end

	return created
end

local function plantCropRows()
	local planted = 0
	local z = PLOT.from.z

	-- Northern row: mostly young/green wheat with a few mature plants.
	for x = 32373, 32382 do
		local itemId = (x == 32375 or x == 32379 or x == 32382) and PLOT.wheatRipeId or PLOT.wheatGreenId
		if createItem(Position(x, 32206, z), itemId) then
			planted = planted + 1
		end
	end

	-- Central row: intentionally broken in the middle to create a small access gap.
	for x = 32373, 32382 do
		if x ~= 32377 and x ~= 32378 then
			local itemId = (x % 2 == 0) and PLOT.wheatGreenId or PLOT.wheatRipeId
			if createItem(Position(x, 32208, z), itemId) then
				planted = planted + 1
			end
		end
	end

	-- Southern row: more mature wheat, with two empty squares so the plot does
	-- not look like a mechanically filled rectangle.
	for x = 32373, 32382 do
		if x ~= 32375 and x ~= 32380 then
			local itemId = (x == 32373 or x == 32378) and PLOT.wheatGreenId or PLOT.wheatRipeId
			if createItem(Position(x, 32210, z), itemId) then
				planted = planted + 1
			end
		end
	end

	return planted
end

local function decoratePlot()
	local z = PLOT.from.z

	-- Keep decorative plants one tile inside the farm so the measured border
	-- sprites remain visually clean.
	local flowerPositions = {
		Position(32373, 32207, z),
		Position(32382, 32207, z),
		Position(32373, 32211, z),
		Position(32382, 32211, z),
	}

	for _, position in ipairs(flowerPositions) do
		addFlowerPatch(position)
	end
end

local function applyPlot()
	local changedGrounds, removedItems, missingTiles = applyBasePlot()
	local borderItems = applyMeasuredBorders()
	local planted = plantCropRows()
	decoratePlot()

	logger.info(
		"[ThaisFarmingPlotStartup] Urban farm ready: {} grounds changed, {} old decorations removed, {} border items created, {} crops planted, {} missing tiles",
		changedGrounds,
		removedItems,
		borderItems,
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
