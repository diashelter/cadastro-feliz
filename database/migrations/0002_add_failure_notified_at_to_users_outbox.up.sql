BEGIN;

ALTER TABLE users_outbox ADD COLUMN failure_notified_at timestamptz;

COMMIT;
