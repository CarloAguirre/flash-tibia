local thaisFarmingPlot = GlobalEvent("ThaisFarmingPlotStartup")

local PLOT = {
	-- Expanded one additional square to the west. East, south and north stay unchanged.
	from = Position(32370, 32205, 7),
	to = Position(32384, 32213, 7),
	grassGroundId = 106,
	westGroundId = 870,
	southGroundId = 870,
	eastGroundId = 103,
	cornerGroundId = 870,
	dirtGroundId = 950,
	cropGroundId = 952,
	wheatRipeId = 3653,
	borders = {
		-- Exact transition stacks sampled in-game.
		north = { 4531, 4658 },
		-- South keeps ground 870 + item 4656, except for its measured corners.
		south = { 4656 },
		-- East (excluding corners): ground 103 + item 4532.
		east = { 4532 },
		-- West (excluding corners): ground 870 + item 4657.
		west = { 4657 },
	},
	corners = {
		-- Exact corner tiles requested from the sampled map positions.
		northWest = { 4532 }, -- ground 870
		northEast = { 4540, 4662 }, -- unchanged previous sampled NE corner
		southWest = { 4661 }, -- ground 870
		southEast = { 4660 }, -- ground 870
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
				if x == PLOT.from.x and y == PLOT.from.y then
					-- NW: ground 870 + item 4532.
					groundId = PLOT.cornerGroundId
				elseif x == PLOT.from.x and y == PLOT.to.y then
					-- SW: ground 870 + item 4661.
					groundId = PLOT.cornerGroundId
				elseif x == PLOT.to.x and y == PLOT.to.y then
					-- SE: ground 870 + item 4660.
					groundId = PLOT.cornerGroundId
				elseif y == PLOT.to.y then
					-- South excluding corners: ground 870 + item 4656.
					groundId = PLOT.southGroundId
				elseif x == PLOT.from.x then
					-- West excluding corners: ground 870 + item 4657.
					groundId = PLOT.westGroundId
				elseif x == PLOT.to.x and y ~= PLOT.from.y then
					-- East excluding NE/SE corners: ground 103 + item 4532.
					groundId = PLOT.eastGroundId
				elseif isBoundary(x, y) then
					-- North edge and the unchanged NE corner retain ground 106.
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

	-- Straight edges exclude all four corners, which are applied explicitly below.
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
