-- Final validation layer for construction orientation variants.
-- Keep this file small and explicit: only remove mappings that are known to be
-- provisional or cross-material. Positive rotation pairs continue to live in
-- farming_build_enhancements.lua, where the server resolves orientation -> itemId.

if not Farming or not Farming.buildCatalog then
	return
end

local stoneCatalog = Farming.buildCatalog.stone
if stoneCatalog and stoneCatalog.door then
	local config = stoneCatalog.door

	-- 5278/5281 are the same paired closed-door family already used by Wood Door
	-- (see data/libs/tables/doors.lua: 5277/5278/5279 and 5280/5281/5282).
	-- The base Stone Door catalogue entry still points at 5278, so advertising
	-- 5281 as a validated *stone* rotation would merely reuse the wooden door.
	-- Disable that provisional mapping until the real stone door pair is verified.
	if tonumber(config.itemId) == 5278 and tonumber(config.rotatedItemId) == 5281 then
		config.rotatedItemId = nil
	end
end
