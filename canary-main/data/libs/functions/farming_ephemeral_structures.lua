-- Player-built structures are intentionally session-scoped.
-- They continue using player_structures while the server is running because
-- ownership, support, demolition and siege systems depend on those rows. On the
-- next server startup the rows are discarded instead of restoring the world.

if not Farming then
	return
end

function Farming.restoreStructures()
	Farming.structurePositions = {}

	if not db.query("DELETE FROM `player_structures`") then
		logger.error("[Farming] Failed to clear transient player structures on startup.")
		return false
	end

	logger.info("[Farming] Cleared transient player structures on server startup.")
	return true
end
