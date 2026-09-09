function onUpdateDatabase()
	logger.info("Updating database to version 58 (persistent player structures)")

	if not db.query([[
		CREATE TABLE IF NOT EXISTS `player_structures` (
			`id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
			`player_id` INT NOT NULL,
			`material` VARCHAR(16) NOT NULL,
			`structure_type` VARCHAR(16) NOT NULL,
			`item_id` INT UNSIGNED NOT NULL,
			`pos_x` INT NOT NULL,
			`pos_y` INT NOT NULL,
			`pos_z` TINYINT UNSIGNED NOT NULL,
			`created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
			PRIMARY KEY (`id`),
			UNIQUE KEY `player_structures_position_uq` (`pos_x`, `pos_y`, `pos_z`),
			KEY `player_structures_player_idx` (`player_id`),
			CONSTRAINT `player_structures_player_fk`
				FOREIGN KEY (`player_id`) REFERENCES `players` (`id`) ON DELETE CASCADE
		) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
	]]) then
		logger.error("Failed to create player_structures table")
	end
end
