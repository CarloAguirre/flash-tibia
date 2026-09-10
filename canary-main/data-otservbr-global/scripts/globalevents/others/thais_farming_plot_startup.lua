local thaisFarmingPlot = GlobalEvent("ThaisFarmingPlotStartup")

local PLOT = {
	-- Expanded one additional square to the west. East, south and north stay unchanged.
	from = Position(32370, 32205, 7),
	to = Position(32384, 32213, 7),
	grassGroundId = 106,
	westGroundId = 870,
	southGroundId = 870,
	dirtGroundId = 950,
	cropGroundId = 952,
	wheatRipeId = 3653,
	borders = {
		-- Exact transition stacks sampled from the reference farm.
		north = { 4531, 4658 },
		-- The full southern row uses the sampled tile: ground 870 + item 4656.
		south = { 4656 },
		east = { 4532, 4659 },
		-- West edge sampled directly from Thais/reference terrain: ground 870 + item 4657.
		west = { 4657 },
	},
	corners = {
		-- Northern corners keep their exact sampled stacks. The southern row is
		-- intentionally uniform, including both corner squares.
		northWest = { 4539, 4659 },
		northEast = { 4540, 4662 },
	},
}

-- Alternating crop rows and bare dirt create walkable aisles. Every crop placed
-- by this startup overlay is mature wheat; its cut/growing stages are handled by
-- the scythe action after harvest.
local CROP_ROWS = {
	[32206] = true,
	[32208] = true,
	[32210] = true,
	[32212] = true,
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

	-- This area is intentionally repurposed. Remove the old park decorations
	-- and any previous runtime crop/contour items before rebuilding the farm.
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

				local groundId
				if y == PLOT.to.y then
					-- Exact southern reference tile: ground 870 + item 4656.
					groundId = PLOT.southGroundId
				elseif x == PLOT.from.x and y ~= PLOT.from.y then
					-- Exact western reference tile: ground 870 + item 4657.
					-- The NW corner remains the separately sampled corner composition.
					groundId = PLOT.westGroundId
				elseif isBoundary(x, y) then
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

	-- North edge excluding its measured corners.
	for x = PLOT.from.x + 1, PLOT.to.x - 1 do
		created = created + addItems(Position(x, PLOT.from.y, z), PLOT.borders.north)
	end

	-- The entire south row, including both corner squares, is deliberately the
	-- same sampled tile: ground 870 with item 4656 on top.
	for x = PLOT.from.x, PLOT.to.x do
		created = created + addItems(Position(x, PLOT.to.y, z), PLOT.borders.south)
	end

	-- West uses its sampled tile (ground 870 + 4657). East keeps the previous
	-- measured composition. Both stop before the south row, whose tile wins at SW/SE.
	for y = PLOT.from.y + 1, PLOT.to.y - 1 do
		created = created + addItems(Position(PLOT.from.x, y, z), PLOT.borders.west)
		created = created + addItems(Position(PLOT.to.x, y, z), PLOT.borders.east)
	end

	created = created + addItems(Position(PLOT.from.x, PLOT.from.y, z), PLOT.corners.northWest)
	created = created + addItems(Position(PLOT.to.x, PLOT.from.y, z), PLOT.corners.northEast)

	return created
end

local function plantWheatRows()
	local planted = 0
	local z = PLOT.from.z

	-- Start every field square fully grown. Harvesting with the scythe changes
	-- 3653 -> 3651 for 2 s -> 3652 for 2 s -> 3653 again.
	for y in pairs(CROP_ROWS) do
		for x = PLOT.from.x + 1, PLOT.to.x - 1 do
			if createItem(Position(x, y, z), PLOT.wheatRipeId) then
				planted = planted + 1
			end
		end
	end

	return planted
end

local function applyPlot()
	local changedGrounds, removedItems, missingTiles = applyBasePlot()
	local contourItems = applyMeasuredContour()
	local planted = plantWheatRows()

	logger.info(
		"[ThaisFarmingPlotStartup] Wheat farm ready: {} grounds changed, {} old items removed, {} contour items created, {} wheat planted, {} missing tiles",
		changedGrounds,
		removedItems,
		contourItems,
		planted,
		missingTiles
	)
end

function thaisFarmingPlot.onStartup()
	-- The OTBM remains the immutable base. Every restart rebuilds this small
	-- farming overlay after the world has loaded.
	applyPlot()
	return true
end

thaisFarmingPlot:register()
