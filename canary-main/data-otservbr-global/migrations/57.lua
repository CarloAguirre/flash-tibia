function onUpdateDatabase()
	logger.info("Updating database to version 57 (farming materials wallet)")

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `player_materials` (
			`player_id` INT NOT NULL,
			`material` VARCHAR(32) NOT NULL,
			`amount` BIGINT UNSIGNED NOT NULL DEFAULT 0,
			`updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
			PRIMARY KEY (`player_id`, `material`),
			CONSTRAINT `player_materials_player_fk`
				FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
	]]) then
		logger.error("Failed to create player_materials table")
	end
end
