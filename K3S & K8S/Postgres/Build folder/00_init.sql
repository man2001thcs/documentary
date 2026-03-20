CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '123456';
SELECT pg_create_physical_replication_slot('replication_slot');