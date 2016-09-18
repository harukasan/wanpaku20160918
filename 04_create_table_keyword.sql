CREATE TABLE `keyword` (
  `name` varchar(191) COLLATE utf8mb4_bin NOT NULL,
  `prefix` varchar(1) COLLATE utf8mb4_bin NOT NULL,
  PRIMARY KEY (`name`),
  KEY `prefix` (`prefix`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

INSERT IGNORE INTO `keyword` (name, prefix) SELECT DISTINCT e.keyword, LEFT(e.keyword, 2) FROM entry AS e;
