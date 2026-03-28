CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    email TEXT NOT NULL,
    username TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    is_confirmed BOOLEAN DEFAULT FALSE NOT NULL,
    confirmation_token TEXT DEFAULT NULL,
    password_reset_token TEXT DEFAULT NULL,
    password_reset_token_expires_at TIMESTAMPTZ DEFAULT NULL,
    failed_login_attempts INT DEFAULT 0 NOT NULL,
    locked_at TIMESTAMPTZ DEFAULT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE UNIQUE INDEX users_email_idx ON users ((LOWER(email)));
CREATE UNIQUE INDEX users_username_idx ON users (username);
CREATE INDEX users_confirmation_token_idx ON users (confirmation_token);
CREATE INDEX users_password_reset_token_idx ON users (password_reset_token);
