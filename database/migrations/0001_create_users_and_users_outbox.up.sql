BEGIN;

CREATE TABLE users (
    id         uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    name       varchar(255) NOT NULL,
    email      varchar(254) NOT NULL,
    created_at timestamptz  NOT NULL DEFAULT now(),
    updated_at timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT users_email_unique UNIQUE (email),
    CONSTRAINT users_email_lowercase CHECK (email = lower(email))
);

CREATE TABLE users_outbox (
    id           uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      uuid         NOT NULL REFERENCES users (id),
    event_type   varchar(100) NOT NULL,
    payload      jsonb        NOT NULL,
    status       varchar(20)  NOT NULL DEFAULT 'pending',
    attempts     integer      NOT NULL DEFAULT 0,
    last_error   text,
    available_at timestamptz  NOT NULL DEFAULT now(),
    published_at timestamptz,
    processed_at timestamptz,
    created_at   timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT users_outbox_status_valid
        CHECK (status IN ('pending', 'published', 'processed', 'failed')),
    CONSTRAINT users_outbox_attempts_positive CHECK (attempts >= 0)
);

CREATE INDEX users_outbox_user_id_index
    ON users_outbox (user_id);

CREATE INDEX users_outbox_pending_index
    ON users_outbox (available_at) WHERE status = 'pending';

CREATE INDEX users_outbox_published_index
    ON users_outbox (published_at) WHERE status = 'published';

COMMIT;
