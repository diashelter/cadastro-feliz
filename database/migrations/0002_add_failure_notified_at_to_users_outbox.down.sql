BEGIN;

ALTER TABLE users_outbox DROP COLUMN failure_notified_at;

COMMIT;
