CREATE TABLE `html_cache` (
	  `hash` varchar(191) NOT NULL,
	  `html` mediumtext COLLATE utf8mb4_bin NOT NULL,
	  PRIMARY KEY (`hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin
