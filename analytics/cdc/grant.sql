-- What Debezium may read in one database, and the publication it streams from.
-- Run in each database, as the owner of its tables, after the apps have migrated:
--   psql -d chat -v tables='users, messages' -f analytics/cdc/grant.sql
GRANT CONNECT ON DATABASE :"DBNAME" TO debezium;
GRANT SELECT ON :tables TO debezium;
CREATE PUBLICATION botchat_cdc FOR TABLE :tables;
