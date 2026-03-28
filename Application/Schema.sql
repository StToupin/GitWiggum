CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE users (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    email TEXT NOT NULL,
    username TEXT NOT NULL,
    password_hash TEXT NOT NULL,
    is_confirmed BOOLEAN DEFAULT FALSE NOT NULL,
    confirmation_token TEXT DEFAULT NULL,
    password_reset_token TEXT DEFAULT NULL,
    password_reset_token_expires_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    ssh_public_key TEXT DEFAULT NULL,
    failed_login_attempts INT DEFAULT 0 NOT NULL,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE UNIQUE INDEX users_email_idx ON users ((LOWER(email)));
CREATE UNIQUE INDEX users_username_idx ON users (username);
CREATE INDEX users_confirmation_token_idx ON users (confirmation_token);
CREATE INDEX users_password_reset_token_idx ON users (password_reset_token);

CREATE TABLE repositories (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY NOT NULL,
    owner_user_id UUID NOT NULL,
    name TEXT NOT NULL,
    description TEXT DEFAULT NULL,
    is_private BOOLEAN DEFAULT FALSE NOT NULL,
    default_branch TEXT DEFAULT 'main' NOT NULL,
    latest_commit_sha TEXT DEFAULT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

ALTER TABLE repositories ADD CONSTRAINT repositories_ref_owner_user_id FOREIGN KEY (owner_user_id) REFERENCES users (id) ON DELETE CASCADE;
CREATE UNIQUE INDEX repositories_owner_user_id_name_idx ON repositories (owner_user_id, LOWER(name));
CREATE INDEX repositories_owner_user_id_idx ON repositories (owner_user_id);
