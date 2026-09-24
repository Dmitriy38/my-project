-- Таблицы реального времени для AMI-поллера (БД pbxanalytics).
-- Таблицы rawdata и analytics создаёт штатный модуль BitATS, здесь их нет.

CREATE TABLE IF NOT EXISTS `rt_queue_status` (
  `ts` datetime NOT NULL,
  `queue` varchar(20) NOT NULL,
  `calls_waiting` int(11) DEFAULT 0,
  `max_wait_sec` int(11) DEFAULT 0,
  `members_avail` int(11) DEFAULT 0,
  `members_busy` int(11) DEFAULT 0,
  `members_paused` int(11) DEFAULT 0,
  PRIMARY KEY (`ts`,`queue`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE IF NOT EXISTS `rt_member_status` (
  `ts` datetime NOT NULL,
  `queue` varchar(20) NOT NULL,
  `ext` varchar(20) NOT NULL,
  `name` varchar(64) DEFAULT NULL,
  `paused` tinyint(4) NOT NULL DEFAULT 0,
  `ami_status` tinyint(4) NOT NULL DEFAULT 0,
  PRIMARY KEY (`ts`,`queue`,`ext`),
  KEY `idx_ts` (`ts`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

CREATE TABLE IF NOT EXISTS `rt_queue_entries` (
  `ts` datetime NOT NULL,
  `queue` varchar(20) NOT NULL,
  `position` int(11) NOT NULL,
  `callerid` varchar(50) DEFAULT NULL,
  `wait_sec` int(11) DEFAULT 0,
  PRIMARY KEY (`ts`,`queue`,`position`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_general_ci;

-- Права штатному модулю аналитики: GRANT принимает только одну таблицу за команду,
-- поэтому отдельная команда на каждую таблицу.
GRANT ALL ON pbxanalytics.rawdata   TO 'analyticsUser'@'localhost';
GRANT ALL ON pbxanalytics.analytics TO 'analyticsUser'@'localhost';
FLUSH PRIVILEGES;

-- Рекомендуется: отдельный пользователь только на чтение для Grafana.
-- CREATE USER 'grafana_ro'@'<GRAFANA_HOST>' IDENTIFIED BY '<CHANGE_ME>';
-- GRANT SELECT ON pbxanalytics.analytics        TO 'grafana_ro'@'<GRAFANA_HOST>';
-- GRANT SELECT ON pbxanalytics.rt_queue_status  TO 'grafana_ro'@'<GRAFANA_HOST>';
-- GRANT SELECT ON pbxanalytics.rt_member_status TO 'grafana_ro'@'<GRAFANA_HOST>';
-- GRANT SELECT ON pbxanalytics.rt_queue_entries TO 'grafana_ro'@'<GRAFANA_HOST>';
-- FLUSH PRIVILEGES;
