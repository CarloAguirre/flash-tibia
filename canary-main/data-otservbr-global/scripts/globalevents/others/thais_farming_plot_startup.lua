local thaisFarmingPlot = GlobalEvent("ThaisFarmingPlotStartup")

local PLOT = {
	-- Expanded one square to the west, east and south. North stays unchanged.
	from = Position(32371, 32205, 7),
	to = Position(32384, 32213, 7),
	dirtGroundId = 950,
	cropGroundId = 952,
	wheatRipeId = 3653,
	borders = {
		-- Keep only the dirt transition piece. The 4656-4662 grass overlays are
		-- intentionally omitted so the original map ground remains visible.
		north = { 4531 },
		south = { 4533 },
		east = { 4532 },
		west = { 4534 },
	},
	corners = {
		-- Same rule for corners: dirt transition only, no additional grass layer.
		northWest = { 4539 },
		northEast = { 4540 },
		southWest = { 4541 },
		southEast = { 4542 },
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
	local preservedBoundaryGrounds = 0

	for x = PLOT.from.x, PLOT.to.x do
		for y = PLOT.from.y, PLOT.to.y do
			local position = Position(x, y, PLOT.from.z)
			local tile = Tile(position)
			if not tile then
				missingTiles = missingTiles + 1
			else
				removedItems = removedItems + clearTopItems(tile)

				if isBoundary(x, y) then
					-- Do NOT transform the perimeter ground. The original OTBM floor
					-- stays visible underneath the dirt-edge sprite.
					preservedBoundaryGrounds = preservedBoundaryGrounds + 1
				else
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
	end

	return changedGrounds, removedItems, missingTiles, preservedBoundaryGrounds
end

local function applyMeasuredContour()
	local created = 0
	local z = PLOT.from.z

	-- Straight edges; corners are applied separately. Only the dirt transition
	-- sprite is created, allowing each tile's native map ground to show through.
	for x = PLOT.from.x + 1, PLOT.to.x - 1 do
		created = created + addItems(Position(x, PLOT.from.y, z), PLOT.borders.north)
		created = created + addItems(Position(x, PLOT.to.y, z), PLOT.borders.south)
	end

	for y = PLOT.from.y + 1, PLOT.to.y - 1 do
		created = created + addItems(Position(PLOT.from.x, y, z), PLOT.borders.west)
		created = created + addItems(Position(PLOT.to.x, y, z), PLOT.borders.east)
	end

	created = created + addItems(Position(PLOT.from.x, PLOT.from.y, z), PLOT.corners.northWest)
	created = created + addItems(Position(PLOT.to.x, PLOT.from.y, z), PLOT.corners.northEast)
	created = created + addItems(Position(PLOT.from.x, PLOT.to.y, z), PLOT.corners.southWest)
	created = created + addItems(Position(PLOT.to.x, PLOT.to.y, z), PLOT.corners.southEast)

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
	local changedGrounds, removedItems, missingTiles, preservedBoundaryGrounds = applyBasePlot()
	local contourItems = applyMeasuredContour()
	local planted = plantWheatRows()

	logger.info(
		"[ThaisFarmingPlotStartup] Wheat farm ready: {} grounds changed, {} perimeter grounds preserved, {} old items removed, {} contour items created, {} wheat planted, {} missing tiles",
		changedGrounds,
		preservedBoundaryGrounds,
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
