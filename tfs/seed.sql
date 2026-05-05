-- Initial seed for development. Loaded by the MariaDB image after schema.sql.
-- admin / admin (SHA1 of "admin")
INSERT IGNORE INTO `accounts` (`id`, `name`, `password`, `type`, `email`, `creation`)
VALUES (1, 'admin', SHA1('admin'), 5, 'admin@local', UNIX_TIMESTAMP());

-- Knight named "Carlo" in town 1, level 8.
-- Most columns have schema defaults; we only set the meaningful ones.
INSERT IGNORE INTO `players` (
    `id`, `name`, `group_id`, `account_id`, `level`, `vocation`,
    `health`, `healthmax`, `experience`,
    `mana`, `manamax`, `town_id`, `cap`
) VALUES (
    1, 'Carlo', 1, 1, 8, 4,
    185, 185, 4200,
    35, 35, 1, 470
);
