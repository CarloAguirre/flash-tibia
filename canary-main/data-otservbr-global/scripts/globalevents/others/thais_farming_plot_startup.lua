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
		-- Exact transition stacks sampled from the reference farm.
		north = { 4531, 4658 },
		south = { 4533, 4656 },
		east = { 4532, 4659 },
		west = { 4534, 4657 },
	},
	corners = {
		-- Exact corner stacks sampled from the reference farm.
		northWest = { 4539, 4659 },
		northEast = { 4540, 4662 },
		southWest = { 4541, 4661 },
		southEast = { 4542, 4660 },
	},
}

local CROP_ROWS = {
	[32206] = true,
	[32208] = true,
	[32210] = true,
}

local function isBoundary(x, y)
	return x == PLOT.from.x or x == PLOT.to.x or y == PLOT.from.y or y == PLOT.to.y
end

local function clearTopItems(tile)
	local removed = 0
	local items = tile:getItems()
	if not items then
		return removed
	end

	-- This park is intentionally repurposed. Remove the old trees, bushes,
	-- statue/fountain pieces and other top decorations before rebuilding it.
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

				-- Every perimeter square, including the four corners, uses the same
				-- grass ground (106) as the reference farm. The dirt shape itself is
				-- drawn by the measured transition items layered on top.
				local groundId
				if isBoundary(x, y) then
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

local function applyMeasuredContour()
	local created = 0
	local z = PLOT.from.z

	-- Straight edges. Corners are excluded here and applied explicitly below.
	for x = PLOT.from.x + 1, PLOT.to.x - 1 do
		created = created + addItems(Position(x, PLOT.from.y, z), PLOT.borders.north)
		created = created + addItems(Position(x, PLOT.to.y, z), PLOT.borders.south)
	end

	for y = PLOT.from.y + 1, PLOT.to.y - 1 do
		created = created + addItems(Position(PLOT.from.x, y, z), PLOT.borders.west)
		created = created + addItems(Position(PLOT.to.x, y, z), PLOT.borders.east)
	end

	-- Exact corner pieces measured from the same reference farm.
	created = created + addItems(Position(PLOT.from.x, PLOT.from.y, z), PLOT.corners.northWest)
	created = created + addItems(Position(PLOT.to.x, PLOT.from.y, z), PLOT.corners.northEast)
	created = created + addItems(Position(PLOT.from.x, PLOT.to.y, z), PLOT.corners.southWest)
	created = created + addItems(Position(PLOT.to.x, PLOT.to.y, z), PLOT.corners.southEast)

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

	-- Keep decorative plants one tile inside so the measured dirt contour stays
	-- visually clean and readable around the whole plot.
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
	local contourItems = applyMeasuredContour()
	local planted = plantCropRows()
	decoratePlot()

	logger.info(
		"[ThaisFarmingPlotStartup] Urban farm ready: {} grounds changed, {} old decorations removed, {} contour items created, {} crops planted, {} missing tiles",
		changedGrounds,
		removedItems,
		contourItems,
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
