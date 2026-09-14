function onUpdateDatabase()
	logger.info("Updating database to version 59 (allow siege overlays on platform tiles)")

	if not db.query("ALTER TABLE `player_structures` DROP INDEX `player_structures_position_uq`;") then
		logger.error("Failed to drop player_structures position-only unique index")
		return
	end

	if not db.query("ALTER TABLE `player_structures` ADD UNIQUE KEY `player_structures_position_type_uq` (`pos_x`, `pos_y`, `pos_z`, `structure_type`);") then
		logger.error("Failed to create player_structures position/type unique index")
	end
end
